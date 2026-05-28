# docker/debezium/Dockerfile
# Extiende la imagen oficial de Debezium Connect agregando:
#   1. debezium-connector-jdbc  — JDBC Sink para replicar hacia MySQL
#   2. mysql-connector-j        — driver JDBC de MySQL requerido por el sink
#
# Versiones alineadas con la imagen base (Debezium 2.7.x).
FROM quay.io/debezium/connect:2.7

USER root

# ── Debezium JDBC Sink Connector ─────────────────────────────────────────────
# El plugin incluye el conector y sus dependencias (sin el driver del target DB).
ENV JDBC_CONNECTOR_VERSION=2.7.3.Final
RUN curl -sfSL \
    "https://repo1.maven.org/maven2/io/debezium/debezium-connector-jdbc/${JDBC_CONNECTOR_VERSION}/debezium-connector-jdbc-${JDBC_CONNECTOR_VERSION}-plugin.tar.gz" \
    -o /tmp/jdbc-plugin.tar.gz \
    && tar -xzf /tmp/jdbc-plugin.tar.gz -C "${KAFKA_CONNECT_PLUGINS_DIR}" \
    && rm /tmp/jdbc-plugin.tar.gz

# ── MySQL JDBC Driver ─────────────────────────────────────────────────────────
# El conector JDBC no incluye el driver del motor destino; hay que agregarlo
# dentro del directorio del plugin para que Kafka Connect lo cargue juntos.
ENV MYSQL_CONNECTOR_VERSION=8.4.0
RUN curl -sfSL \
    "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${MYSQL_CONNECTOR_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar" \
    -o "${KAFKA_CONNECT_PLUGINS_DIR}/debezium-connector-jdbc/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar"

USER 1001
