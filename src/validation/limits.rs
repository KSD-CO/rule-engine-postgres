/// Maximum input size (1MB)
pub const MAX_INPUT_SIZE: usize = 1_000_000;

/// Check if input size is within limits
pub fn check_size_limit(input: &str, limit: usize) -> Result<(), String> {
    if input.len() > limit {
        return Err(format!(
            "Input too large: {} bytes (max {} bytes)",
            input.len(),
            limit
        ));
    }
    Ok(())
}

/// Check if input is empty
pub fn check_not_empty(input: &str, field_name: &str) -> Result<(), String> {
    if input.is_empty() {
        return Err(format!("{} cannot be empty", field_name));
    }
    Ok(())
}
