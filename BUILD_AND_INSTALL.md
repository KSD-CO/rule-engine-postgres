# Guide to Build and Install Rust Extension for Postgres

## 1. Build the extension

In the project directory, run the following command to build the extension for Postgres 16:

```bash
cargo build --features pg16
```

## 2. Copy required files to Postgres system directories

After building, copy the following files:

- Shared library `.so`:
  ```bash
  sudo cp target/debug/librule_engine_postgre_extensions.so /usr/lib/postgresql/16/lib/
  ```
- Control file:
  ```bash
  sudo cp rule_engine_postgre_extensions.control /usr/share/postgresql/16/extension/
  ```
- SQL install script:
  ```bash
  sudo cp rule_engine_postgre_extensions--0.1.0.sql /usr/share/postgresql/16/extension/
  ```

## 3. Restart Postgres (if needed)
```bash
sudo systemctl restart postgresql
```

## 4. Create the extension in psql

Enter psql as the postgres user:
```bash
sudo -u postgres psql
```

Then run:
```sql
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions;
CREATE EXTENSION rule_engine_postgre_extensions;
\df run_rule_engine
```

## 5. Test the function

Example query:
```sql
SELECT run_rule_engine('{"a":1}', 'rule "Test" { when a == 1 then print("OK") }');
```

---
If you encounter errors or need more detailed instructions, check the file paths or send the error message for support.
