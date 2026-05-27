#!/usr/bin/env python3
"""
migrate_pg_to_sqlserver.py
Migra datos de PostgreSQL (pg1) a SQL Server (tp-sqlserver).

Cubre las 4 bases de datos:
  - treepruning  → dbo schema
  - strapi       → dbo schema (el schema lo crea Strapi al arrancar)
  - sonarqube    → dbo schema (el schema lo crea SonarQube al arrancar)

Keycloak se migra por separado con kc.sh export/import (ver migrate-to-sqlserver.sh).

Uso:
  docker run --rm --network treepruning-net \
    -e PG_HOST=pg1 -e PG_USER=postgres -e PG_PASSWORD=<pw> \
    -e SQL_HOST=tp-sqlserver -e SQL_USER=sa -e SQL_PASSWORD=<pw> \
    -v $(pwd):/app \
    python:3.12-slim \
    sh -c "pip install psycopg2-binary pymssql -q && python /app/migrate_pg_to_sqlserver.py"
"""

import os
import sys
import psycopg2
import pymssql
from psycopg2.extras import RealDictCursor
from datetime import datetime, date
from decimal import Decimal
import uuid

# ── Config ────────────────────────────────────────────────────────────────────

PG_HOST  = os.environ.get("PG_HOST",  "pg1")
PG_PORT  = int(os.environ.get("PG_PORT", "5432"))
PG_USER  = os.environ.get("PG_USER",  "postgres")
PG_PASS  = os.environ.get("PG_PASSWORD", "")

SQL_HOST = os.environ.get("SQL_HOST", "tp-sqlserver")
SQL_PORT = int(os.environ.get("SQL_PORT", "1433"))
SQL_USER = os.environ.get("SQL_USER", "sa")
SQL_PASS = os.environ.get("SQL_PASSWORD", "")

# Databases to migrate (pg_name → sqlserver_name)
# Keycloak is excluded — use kc.sh export/import instead
DATABASES = {
    "treepruning": "treepruning",
    "strapi":      "strapi",
    "sonarqube":   "sonarqube",
}

# Tables to migrate per database.
# treepruning: use the treepruning schema (maps to dbo in SQL Server)
# strapi / sonarqube: public schema (SQL Server schema created by each service)
TABLES = {
    "treepruning": [
        "country", "state", "municipality", "sector",
        "document", "family", "type", "risk", "status", "tool",
        "programming", "tree", "pqr", "pruning", "pruning_tool",
        "person", "manager", "quadrille", "administrator", "operator",
        "notification_tokens", "notification_history",
    ],
    # strapi and sonarqube: migrate ALL tables automatically
    "strapi":      None,
    "sonarqube":   None,
}

# Schema prefix in PostgreSQL per database
PG_SCHEMA = {
    "treepruning": "treepruning",
    "strapi":      "public",
    "sonarqube":   "public",
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def pg_connect(db_name):
    return psycopg2.connect(
        host=PG_HOST, port=PG_PORT,
        user=PG_USER, password=PG_PASS,
        dbname=db_name
    )

def sql_connect(db_name):
    return pymssql.connect(
        server=SQL_HOST, port=SQL_PORT,
        user=SQL_USER, password=SQL_PASS,
        database=db_name
    )

def get_tables(pg_cur, schema):
    pg_cur.execute("""
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = %s
          AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """, (schema,))
    return [row[0] for row in pg_cur.fetchall()]

def get_columns(pg_cur, schema, table):
    pg_cur.execute("""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s
        ORDER BY ordinal_position
    """, (schema, table))
    return pg_cur.fetchall()

def convert_value(val, data_type):
    """Convierte tipos de PostgreSQL a tipos compatibles con SQL Server."""
    if val is None:
        return None
    if data_type in ("uuid",):
        return str(val)
    if isinstance(val, bool):
        return 1 if val else 0
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, (datetime, date)):
        return val
    return val

def migrate_table(pg_db, sql_db, pg_schema, table_name):
    pg_conn  = pg_connect(pg_db)
    sql_conn = sql_connect(sql_db)
    pg_cur   = pg_conn.cursor(cursor_factory=RealDictCursor)
    sql_cur  = sql_conn.cursor()

    try:
        # Get columns
        meta_cur = pg_conn.cursor()
        columns  = get_columns(meta_cur, pg_schema, table_name)
        col_names  = [c[0] for c in columns]
        col_types  = {c[0]: c[1] for c in columns}
        meta_cur.close()

        # Read from PostgreSQL
        pg_cur.execute(f'SELECT * FROM "{pg_schema}"."{table_name}"')
        rows = pg_cur.fetchall()

        if not rows:
            print(f"  {table_name}: vacía, omitida")
            return 0

        # Check if SQL Server table already has data
        sql_cur.execute(f"SELECT COUNT(*) FROM dbo.[{table_name}]")
        existing = sql_cur.fetchone()[0]
        if existing > 0:
            print(f"  {table_name}: ya tiene {existing} filas, omitida")
            return 0

        # Build INSERT
        placeholders = ", ".join(["%s"] * len(col_names))
        col_list     = ", ".join([f"[{c}]" for c in col_names])
        insert_sql   = f"INSERT INTO dbo.[{table_name}] ({col_list}) VALUES ({placeholders})"

        # Disable identity insert if needed (for tables with INT IDENTITY)
        sql_cur.execute(f"""
            IF EXISTS (
                SELECT 1 FROM sys.identity_columns
                WHERE OBJECT_NAME(object_id) = '{table_name}'
            )
            SET IDENTITY_INSERT dbo.[{table_name}] ON
        """)

        batch = []
        for row in rows:
            converted = tuple(convert_value(row[c], col_types[c]) for c in col_names)
            batch.append(converted)
            if len(batch) >= 500:
                sql_cur.executemany(insert_sql, batch)
                sql_conn.commit()
                batch = []

        if batch:
            sql_cur.executemany(insert_sql, batch)
            sql_conn.commit()

        # Re-enable identity insert
        sql_cur.execute(f"""
            IF EXISTS (
                SELECT 1 FROM sys.identity_columns
                WHERE OBJECT_NAME(object_id) = '{table_name}'
            )
            SET IDENTITY_INSERT dbo.[{table_name}] OFF
        """)
        sql_conn.commit()

        print(f"  {table_name}: {len(rows)} filas migradas ✓")
        return len(rows)

    except Exception as e:
        sql_conn.rollback()
        print(f"  {table_name}: ERROR — {e}")
        return -1
    finally:
        pg_cur.close()
        sql_cur.close()
        pg_conn.close()
        sql_conn.close()

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    total_rows    = 0
    total_errors  = 0

    for pg_db, sql_db in DATABASES.items():
        print(f"\n{'='*60}")
        print(f"Migrando: {pg_db} → {sql_db}")
        print('='*60)

        # Determine tables to migrate
        tables = TABLES.get(pg_db)
        if tables is None:
            # Migrate all tables in the schema
            try:
                pg_conn = pg_connect(pg_db)
                pg_cur  = pg_conn.cursor()
                tables  = get_tables(pg_cur, PG_SCHEMA[pg_db])
                pg_cur.close()
                pg_conn.close()
            except Exception as e:
                print(f"  No se pudo conectar a {pg_db}: {e}")
                continue

        print(f"  Tablas a migrar: {len(tables)}")

        for table in tables:
            result = migrate_table(pg_db, sql_db, PG_SCHEMA[pg_db], table)
            if result > 0:
                total_rows += result
            elif result == -1:
                total_errors += 1

    print(f"\n{'='*60}")
    print(f"Migración completada")
    print(f"  Total filas migradas: {total_rows}")
    print(f"  Tablas con error:     {total_errors}")
    if total_errors > 0:
        print("  Revisar los errores antes de activar el failover.")
    print('='*60)

    sys.exit(1 if total_errors > 0 else 0)


if __name__ == "__main__":
    main()
