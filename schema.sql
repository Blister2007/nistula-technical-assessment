-- =====================================================================
-- Nistula Unified Messaging Platform - PostgreSQL Schema
-- =====================================================================
-- Designed for a multi-channel guest messaging platform where one guest
-- can reach us on whatsapp, booking.com, airbnb, instagram, or directly,
-- and we want one unified view of every conversation.
--
-- Key decisions explained inline. The hardest call (matching guests
-- across channels) is discussed at the bottom.
-- =====================================================================


-- =====================================================================
-- 1. PROPERTIES
-- =====================================================================
-- Villa B1, Villa B2 etc. Kept separate from messages so we can join
-- property details (rate, address, amenities) into AI prompts without
-- duplicating them.
CREATE TABLE properties (
    property_id     VARCHAR(50) PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    location        VARCHAR(200),
    bedrooms        INTEGER,
    max_guests      INTEGER,
    base_rate_inr   INTEGER,
    metadata        JSONB,                  -- amenities, wifi password, check-in time etc
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);


-- =====================================================================
-- 2. GUESTS
-- =====================================================================
-- One row per real human, NOT one row per channel handle.
-- The matching logic (phone, email, name+booking_ref) decides which
-- channel handles map to which guest. See note at the bottom.
CREATE TABLE guests (
    guest_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(200) NOT NULL,
    primary_phone   VARCHAR(20),
    primary_email   VARCHAR(200),
    country         VARCHAR(100),
    notes           TEXT,                   -- caretaker tips, preferences, "allergic to peanuts"
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_guests_phone ON guests(primary_phone);
CREATE INDEX idx_guests_email ON guests(primary_email);


-- =====================================================================
-- 3. GUEST CHANNEL IDENTITIES
-- =====================================================================
-- Maps a guest to every handle/ID they use across channels.
-- One guest can have a WhatsApp number, an Airbnb user ID, and an
-- Instagram handle - all three rows point to the same guest_id.
CREATE TABLE guest_channel_identities (
    identity_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests(guest_id) ON DELETE CASCADE,
    channel         VARCHAR(50) NOT NULL,   -- whatsapp, booking_com, airbnb, instagram, direct
    channel_handle  VARCHAR(200) NOT NULL,  -- the phone number, OTA user id, IG handle etc
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (channel, channel_handle)
);

CREATE INDEX idx_identities_guest ON guest_channel_identities(guest_id);


-- =====================================================================
-- 4. RESERVATIONS
-- =====================================================================
-- A booking. Linked to a guest and a property. Status tracks the
-- lifecycle so we know if this is a pre-sales lead, an active stay,
-- or a past guest (which matters for how the AI replies).
CREATE TABLE reservations (
    reservation_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_ref     VARCHAR(50) UNIQUE,         -- the human-readable ref like NIS-2024-0891
    guest_id        UUID NOT NULL REFERENCES guests(guest_id),
    property_id     VARCHAR(50) NOT NULL REFERENCES properties(property_id),
    check_in_date   DATE,
    check_out_date  DATE,
    num_guests      INTEGER,
    total_amount_inr INTEGER,
    status          VARCHAR(30) NOT NULL,       -- enquiry, confirmed, checked_in, completed, cancelled
    source_channel  VARCHAR(50),                -- where the booking came from
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_reservations_guest ON reservations(guest_id);
CREATE INDEX idx_reservations_property_dates ON reservations(property_id, check_in_date);
CREATE INDEX idx_reservations_status ON reservations(status);


-- =====================================================================
-- 5. CONVERSATIONS
-- =====================================================================
-- A logical thread. One conversation can span weeks and switch channels.
-- A guest might first message on Instagram (enquiry), then move to
-- WhatsApp after booking - we keep it as ONE conversation so the agent
-- and the AI see the full story.
CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests(guest_id),
    reservation_id  UUID REFERENCES reservations(reservation_id),    -- nullable: enquiries have no booking yet
    property_id     VARCHAR(50) REFERENCES properties(property_id),  -- denormalised for fast filtering
    status          VARCHAR(30) NOT NULL DEFAULT 'open',  -- open, waiting_agent, waiting_guest, resolved
    last_message_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_conversations_guest ON conversations(guest_id);
CREATE INDEX idx_conversations_status ON conversations(status);
CREATE INDEX idx_conversations_last_message ON conversations(last_message_at DESC);


-- =====================================================================
-- 6. MESSAGES
-- =====================================================================
-- THE big table. Every inbound and outbound message lives here.
-- direction tells you who sent it. ai_metadata holds the AI-related
-- fields for inbound messages.
CREATE TABLE messages (
    message_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    direction           VARCHAR(10) NOT NULL,   -- 'inbound' or 'outbound'
    channel             VARCHAR(50) NOT NULL,   -- whatsapp, booking_com, airbnb, instagram, direct
    message_text        TEXT NOT NULL,
    sender_handle       VARCHAR(200),           -- raw handle from the channel (phone, OTA id etc)
    timestamp           TIMESTAMPTZ NOT NULL,   -- when the channel says the message was sent

    -- AI-related fields. NULL for outbound human-typed messages
    -- or for inbound messages we haven't run through the AI yet.
    query_type          VARCHAR(50),            -- pre_sales_availability, complaint etc
    ai_drafted_reply    TEXT,                   -- what the AI suggested
    ai_confidence       NUMERIC(3,2),           -- 0.00 to 1.00
    ai_action           VARCHAR(20),            -- auto_send, agent_review, escalate

    -- Tracks who actually sent the outbound version
    sent_status         VARCHAR(20),            -- pending, auto_sent, agent_edited_sent, agent_drafted_sent
    sent_by_agent_id    UUID,                   -- nullable: NULL means AI auto-sent
    sent_at             TIMESTAMPTZ,

    raw_payload         JSONB,                  -- original webhook payload, for debugging
    created_at          TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT chk_direction CHECK (direction IN ('inbound', 'outbound')),
    CONSTRAINT chk_confidence CHECK (ai_confidence IS NULL OR (ai_confidence >= 0 AND ai_confidence <= 1))
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, timestamp);
CREATE INDEX idx_messages_query_type ON messages(query_type) WHERE query_type IS NOT NULL;
CREATE INDEX idx_messages_low_confidence ON messages(ai_confidence) WHERE ai_confidence < 0.85;
CREATE INDEX idx_messages_pending_review ON messages(ai_action) WHERE ai_action = 'agent_review';


-- =====================================================================
-- 7. AGENTS (for completeness - referenced by messages.sent_by_agent_id)
-- =====================================================================
CREATE TABLE agents (
    agent_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200) NOT NULL,
    email           VARCHAR(200) UNIQUE NOT NULL,
    role            VARCHAR(50),                -- guest_relations, ops_lead, admin
    active          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);


-- =====================================================================
-- DESIGN NOTES
-- =====================================================================
-- 1. Why a separate guest_channel_identities table instead of stuffing
--    whatsapp_number, ig_handle etc as columns on guests?
--    Because the channel list grows. Tomorrow Nistula might add MakeMyTrip,
--    Agoda, a website chat widget. Adding rows is free; adding columns
--    is a migration. Same reason properties has a JSONB metadata column.
--
-- 2. Why is property_id denormalised onto conversations when we could
--    join through reservations? Because most enquiries don't have a
--    reservation yet, but they're still about a specific property.
--    And it makes the most common query - "show me all open conversations
--    for Villa B1" - a single index lookup.
--
-- 3. Why store ai_drafted_reply on the inbound message rather than a
--    separate ai_drafts table? Because we always have exactly one draft
--    per inbound message, and the audit trail is "this inbound got this
--    draft". A separate table would be lookups for no payoff.
--
-- 4. Partial indexes (the ones with WHERE clauses) are deliberate. The
--    queries "show me messages flagged for agent review" and "show me
--    low-confidence drafts" run constantly in the agent dashboard. A
--    partial index is much smaller and faster than indexing every row
--    when most rows are auto_send and we don't care about them anymore.
--
-- =====================================================================
-- HARDEST DESIGN DECISION
-- =====================================================================
-- The hardest call was matching guests across channels. The same person
-- might book Villa B1 on booking.com using personal email, then WhatsApp
-- us from a number that has no email attached. Is that one guest or two?
--
-- I chose to make guests its own table separate from channel identities,
-- with a join table in between, because the alternative (one row per
-- channel-handle) means we can never confidently say "this is the same
-- person who stayed with us last June". The cost is that matching is
-- now a process - probably a mix of automated rules (same booking_ref,
-- same phone, same email) and agent-flagged merges for fuzzy cases.
-- But that cost is one-time per guest. The benefit - a single guest
-- profile that compounds in value across stays - is forever.
