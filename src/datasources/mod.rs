// External Data Sources module
// Fetch data from REST APIs in rules with caching and connection pooling

pub mod client;
pub mod models;

pub use client::{DataSourceClient, HttpMethod};
pub use models::{DataSource, DataSourceRequest, DataSourceResponse};
