// Data models for Rule Repository
use serde::{Deserialize, Serialize};

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleDefinition {
    pub id: i32,
    pub name: String,
    pub description: Option<String>,
    pub created_at: String,
    pub created_by: Option<String>,
    pub updated_at: String,
    pub updated_by: Option<String>,
    pub is_active: bool,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleVersion {
    pub id: i32,
    pub rule_id: i32,
    pub version: String,
    pub grl_content: String,
    pub change_notes: Option<String>,
    pub created_at: String,
    pub created_by: Option<String>,
    pub is_default: bool,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleListItem {
    pub id: i32,
    pub name: String,
    pub description: Option<String>,
    pub version: Option<String>,
    pub created_at: String,
    pub is_active: bool,
    pub tags: Option<Vec<String>>,
}
