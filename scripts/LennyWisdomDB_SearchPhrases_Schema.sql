/*
    LennyWisdomDB - Search Phrases Table

    Pre-embedded queries for semantic search - no LIKE wildcards needed.
    Queries phrased conversationally to match how podcast content
    actually discusses these topics.
*/

USE LennyWisdomDB;
GO

-- ============================================================================
-- Search Phrases Table
-- ============================================================================

IF OBJECT_ID('search_phrases', 'U') IS NOT NULL
    DROP TABLE search_phrases;
GO

CREATE TABLE search_phrases (
    search_id INT PRIMARY KEY IDENTITY(1,1),
    search_phrase NVARCHAR(500) NOT NULL,
    search_vector VECTOR(1024) NULL,  -- snowflake-arctic-embed2
    category NVARCHAR(50) NULL,
    created_date DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- ============================================================================
-- Insert search phrases by category
-- Phrased conversationally to match podcast content style
-- ============================================================================

-- Product Strategy (how practitioners actually talk about it)
INSERT INTO search_phrases (category, search_phrase) VALUES
('strategy', 'how to create a product vision that actually inspires the team'),
('strategy', 'examples of good roadmaps and how top PMs build them'),
('strategy', 'how to prioritize when everything feels urgent'),
('strategy', 'signs you have product market fit and how to find it'),
('strategy', 'what bad strategy looks like and how to avoid it'),
('strategy', 'how to say no to feature requests from executives'),
('strategy', 'making hard tradeoffs when you cant do everything'),
('strategy', 'how to think about long term vs short term priorities'),
('strategy', 'building conviction around a product direction'),
('strategy', 'when to pivot vs when to persevere');

-- Leadership & Influence
INSERT INTO search_phrases (category, search_phrase) VALUES
('leadership', 'how to manage up and influence your manager'),
('leadership', 'giving tough feedback without destroying the relationship'),
('leadership', 'building a team that actually ships great products'),
('leadership', 'getting buy-in when you dont have direct authority'),
('leadership', 'handling disagreements with engineering leads'),
('leadership', 'delegating effectively without micromanaging'),
('leadership', 'earning trust with a new team'),
('leadership', 'what separates good product leaders from great ones'),
('leadership', 'dealing with difficult stakeholders'),
('leadership', 'how to run a product org');

-- Career Development
INSERT INTO search_phrases (category, search_phrase) VALUES
('career', 'how to get promoted from PM to senior PM'),
('career', 'should I become a manager or stay as an IC'),
('career', 'breaking into product management from another field'),
('career', 'negotiating compensation and knowing your worth'),
('career', 'building a career that lasts decades'),
('career', 'skills that matter most for PM career growth'),
('career', 'finding the right company and role'),
('career', 'standing out in product manager interviews'),
('career', 'when to leave a job and find something new'),
('career', 'mistakes that hurt PM careers');

-- Growth & Metrics
INSERT INTO search_phrases (category, search_phrase) VALUES
('growth', 'what metrics actually matter for products'),
('growth', 'growing a product from zero users to something real'),
('growth', 'running experiments that give you real answers'),
('growth', 'product led growth and how it actually works'),
('growth', 'keeping users coming back and reducing churn'),
('growth', 'north star metrics and how to pick one'),
('growth', 'building a growth model that compounds'),
('growth', 'activation and onboarding that works'),
('growth', 'viral loops and word of mouth growth'),
('growth', 'pricing strategy and monetization');

-- AI & Future of PM
INSERT INTO search_phrases (category, search_phrase) VALUES
('ai', 'how AI is changing product management'),
('ai', 'building AI products that users actually want'),
('ai', 'why data matters so much for AI features'),
('ai', 'using AI tools to be a better PM'),
('ai', 'what comes next for AI products'),
('ai', 'evaluating whether to add AI to your product'),
('ai', 'AI product development lessons from practitioners'),
('ai', 'prompt engineering and AI UX patterns');

-- Execution & Shipping
INSERT INTO search_phrases (category, search_phrase) VALUES
('execution', 'running meetings that dont waste time'),
('execution', 'writing specs and PRDs that engineers love'),
('execution', 'working with engineers as true partners'),
('execution', 'shipping faster without cutting corners'),
('execution', 'dealing with technical debt decisions'),
('execution', 'scoping projects so they actually finish'),
('execution', 'launches that go well vs launches that fail'),
('execution', 'sprint planning and agile that works');

-- User Research & Discovery
INSERT INTO search_phrases (category, search_phrase) VALUES
('discovery', 'doing user research that changes your mind'),
('discovery', 'customer interviews that reveal real insights'),
('discovery', 'validating ideas before building them'),
('discovery', 'understanding what users actually need'),
('discovery', 'building products people genuinely love'),
('discovery', 'finding problems worth solving'),
('discovery', 'prototyping and testing concepts fast');

-- Culture & Hiring
INSERT INTO search_phrases (category, search_phrase) VALUES
('culture', 'building product culture that attracts talent'),
('culture', 'hiring PMs and what to look for'),
('culture', 'interview questions that reveal great PMs'),
('culture', 'onboarding new PMs so they succeed'),
('culture', 'creating psychological safety on product teams');

-- Founder/Startup specific
INSERT INTO search_phrases (category, search_phrase) VALUES
('startup', 'advice for first time founders'),
('startup', 'fundraising and talking to investors'),
('startup', 'when to hire your first PM'),
('startup', 'startup mistakes to avoid'),
('startup', 'scaling a product org as you grow');

GO

-- ============================================================================
-- Summary stats
-- ============================================================================

SELECT
    category,
    COUNT(*) as phrase_count
FROM search_phrases
GROUP BY category
ORDER BY phrase_count DESC;

SELECT COUNT(*) as total_phrases FROM search_phrases;
GO
