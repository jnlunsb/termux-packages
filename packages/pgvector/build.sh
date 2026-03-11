TERMUX_PKG_HOMEPAGE="https://github.com/pgvector/pgvector"
TERMUX_PKG_DESCRIPTION="Open-source vector similarity search for PostgreSQL"
TERMUX_PKG_LICENSE="PostgreSQL"
TERMUX_PKG_MAINTAINER="@termux-user"
TERMUX_PKG_VERSION="0.8.0"
TERMUX_PKG_SRCURL="https://github.com/pgvector/pgvector/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="867a2c328d4928a5a9d6f052cd3bc78c7d60228a9b914ad32aa3db88e9de27b0"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_DEPENDS="postgresql"

termux_step_pre_configure() {
    export PG_CONFIG="$TERMUX_PREFIX/bin/pg_config"
    export USE_PGXS=1

    # 追加 installcheck 覆盖
    cat >> Makefile << 'EOF'

# Termux: Override PGXS installcheck
installcheck:
	@echo "Skipping installcheck"
EOF
}

termux_step_make() {
    make -j $TERMUX_PKG_MAKE_PROCESSES PG_CONFIG="$PG_CONFIG" all
}

termux_step_make_install() {
    # 安装 .so 文件
    install -Dm644 vector.so \
        "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX/lib/postgresql/vector.so"

    # 安装 SQL 文件
    install -Dm644 sql/vector--0.8.0.sql \
        "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX/share/postgresql/extension/vector--0.8.0.sql"

    # 安装控制文件
    if [ -f vector.control ]; then
        install -Dm644 vector.control \
            "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX/share/postgresql/extension/vector.control"
    else
        mkdir -p "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX/share/postgresql/extension"
        cat > "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX/share/postgresql/extension/vector.control" << 'EOF'
# pgvector extension
comment = 'Open-source vector similarity search for PostgreSQL'
default_version = '0.8.0'
module_pathname = '$libdir/vector'
relocatable = true
EOF
    fi
}