
CREATE TABLE properties (
    property_id     VARCHAR(50) PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    location        VARCHAR(200),
    bedrooms        INTEGER,
    max_guests      INTEGER,
    base_rate_inr   INTEGER,
    metadata        JSONB,                  
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);


CREATE TABLE guests (
    guest_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       VARCHAR(200) NOT NULL,
    primary_phone   VARCHAR(20),
    primary_email   VARCHAR(200),
    country         VARCHAR(100),
    notes           TEXT,                   
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_guests_phone ON guests(primary_phone);
CREATE INDEX idx_guests_email ON guests(primary_email);



CREATE TABLE guest_channel_identities (
    identity_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests(guest_id) ON DELETE CASCADE,
    channel         VARCHAR(50) NOT NULL,   
    channel_handle  VARCHAR(200) NOT NULL,  
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (channel, channel_handle)
);

CREATE INDEX idx_identities_guest ON guest_channel_identities(guest_id);


CREATE TABLE reservations (
    reservation_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_ref     VARCHAR(50) UNIQUE,         
    guest_id        UUID NOT NULL REFERENCES guests(guest_id),
    property_id     VARCHAR(50) NOT NULL REFERENCES properties(property_id),
    check_in_date   DATE,
    check_out_date  DATE,
    num_guests      INTEGER,
    total_amount_inr INTEGER,
    status          VARCHAR(30) NOT NULL,       
    source_channel  VARCHAR(50),                
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_reservations_guest ON reservations(guest_id);
CREATE INDEX idx_reservations_property_dates ON reservations(property_id, check_in_date);
CREATE INDEX idx_reservations_status ON reservations(status);


CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests(guest_id),
    reservation_id  UUID REFERENCES reservations(reservation_id),    
    property_id     VARCHAR(50) REFERENCES properties(property_id),  
    status          VARCHAR(30) NOT NULL DEFAULT 'open', 
    last_message_at TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_conversations_guest ON conversations(guest_id);
CREATE INDEX idx_conversations_status ON conversations(status);
CREATE INDEX idx_conversations_last_message ON conversations(last_message_at DESC);



CREATE TABLE messages (
    message_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    direction           VARCHAR(10) NOT NULL,   
    channel             VARCHAR(50) NOT NULL,   
    message_text        TEXT NOT NULL,
    sender_handle       VARCHAR(200),          
    timestamp           TIMESTAMPTZ NOT NULL,   

   
    query_type          VARCHAR(50),            
    ai_drafted_reply    TEXT,                  
    ai_confidence       NUMERIC(3,2),          
    ai_action           VARCHAR(20),           

    
    sent_status         VARCHAR(20),            
    sent_by_agent_id    UUID,                   
    sent_at             TIMESTAMPTZ,

    raw_payload         JSONB,                 
    created_at          TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT chk_direction CHECK (direction IN ('inbound', 'outbound')),
    CONSTRAINT chk_confidence CHECK (ai_confidence IS NULL OR (ai_confidence >= 0 AND ai_confidence <= 1))
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, timestamp);
CREATE INDEX idx_messages_query_type ON messages(query_type) WHERE query_type IS NOT NULL;
CREATE INDEX idx_messages_low_confidence ON messages(ai_confidence) WHERE ai_confidence < 0.85;
CREATE INDEX idx_messages_pending_review ON messages(ai_action) WHERE ai_action = 'agent_review';



CREATE TABLE agents (
    agent_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200) NOT NULL,
    email           VARCHAR(200) UNIQUE NOT NULL,
    role            VARCHAR(50),               
    active          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);


-e guest
-- profile that compounds in value across stays - is forever.
