// Version management utilities
use crate::error::RuleEngineError;

/// Parse semantic version into components
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SemanticVersion {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
    pub pre_release: Option<String>,
}

impl SemanticVersion {
    pub fn parse(version: &str) -> Result<Self, RuleEngineError> {
        let parts: Vec<&str> = version.split('-').collect();
        let version_part = parts[0];
        let pre_release = if parts.len() > 1 {
            Some(parts[1].to_string())
        } else {
            None
        };

        let numbers: Vec<&str> = version_part.split('.').collect();
        if numbers.len() != 3 {
            return Err(RuleEngineError::InvalidInput(format!(
                "Invalid version format: {}",
                version
            )));
        }

        Ok(SemanticVersion {
            major: numbers[0].parse().map_err(|_| {
                RuleEngineError::InvalidInput(format!("Invalid major version: {}", numbers[0]))
            })?,
            minor: numbers[1].parse().map_err(|_| {
                RuleEngineError::InvalidInput(format!("Invalid minor version: {}", numbers[1]))
            })?,
            patch: numbers[2].parse().map_err(|_| {
                RuleEngineError::InvalidInput(format!("Invalid patch version: {}", numbers[2]))
            })?,
            pre_release,
        })
    }

    pub fn to_string(&self) -> String {
        match &self.pre_release {
            Some(pre) => format!("{}.{}.{}-{}", self.major, self.minor, self.patch, pre),
            None => format!("{}.{}.{}", self.major, self.minor, self.patch),
        }
    }

    /// Increment patch version
    pub fn increment_patch(&self) -> Self {
        SemanticVersion {
            major: self.major,
            minor: self.minor,
            patch: self.patch + 1,
            pre_release: None,
        }
    }

    /// Increment minor version
    pub fn increment_minor(&self) -> Self {
        SemanticVersion {
            major: self.major,
            minor: self.minor + 1,
            patch: 0,
            pre_release: None,
        }
    }

    /// Increment major version
    pub fn increment_major(&self) -> Self {
        SemanticVersion {
            major: self.major + 1,
            minor: 0,
            patch: 0,
            pre_release: None,
        }
    }
}

impl PartialOrd for SemanticVersion {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SemanticVersion {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.major
            .cmp(&other.major)
            .then(self.minor.cmp(&other.minor))
            .then(self.patch.cmp(&other.patch))
            .then_with(|| {
                match (&self.pre_release, &other.pre_release) {
                    (None, None) => std::cmp::Ordering::Equal,
                    (Some(_), None) => std::cmp::Ordering::Less, // Pre-release is less than release
                    (None, Some(_)) => std::cmp::Ordering::Greater,
                    (Some(a), Some(b)) => a.cmp(b),
                }
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_version() {
        let v = SemanticVersion::parse("1.2.3").unwrap();
        assert_eq!(v.major, 1);
        assert_eq!(v.minor, 2);
        assert_eq!(v.patch, 3);
        assert_eq!(v.pre_release, None);

        let v = SemanticVersion::parse("1.0.0-beta").unwrap();
        assert_eq!(v.pre_release, Some("beta".to_string()));
    }

    #[test]
    fn test_version_comparison() {
        let v1 = SemanticVersion::parse("1.0.0").unwrap();
        let v2 = SemanticVersion::parse("1.0.1").unwrap();
        let v3 = SemanticVersion::parse("1.1.0").unwrap();
        let v4 = SemanticVersion::parse("2.0.0").unwrap();

        assert!(v1 < v2);
        assert!(v2 < v3);
        assert!(v3 < v4);
    }

    #[test]
    fn test_increment_version() {
        let v = SemanticVersion::parse("1.2.3").unwrap();

        assert_eq!(v.increment_patch().to_string(), "1.2.4");
        assert_eq!(v.increment_minor().to_string(), "1.3.0");
        assert_eq!(v.increment_major().to_string(), "2.0.0");
    }
}
