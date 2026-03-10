TERMUX_PKG_HOMEPAGE="https://github.com/pgvector/pgvector"
TERMUX_PKG_DESCRIPTION="Open-source vector similarity search for Pgvector"
TERMUX_PKG_LICENSE="PostgreSQL"
TERMUX_PKG_MAINTAINER="Julius"
TERMUX_PKG_VERSION="0.8.0"

TERMUX_PKG_SRCURL="https://github.com/pgvector/pgvector/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="867a2c328d4928a5a9d6f052cd3bc78c7d60228f7b1c60d61de1cd8bfce117bd"
TERMUX_PKG_DEPENDS="postgresql"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
    export PG_CONFIG="$TERMUX_PREFIX/bin/pg_config"
}

termux_step_make() {
    make -j "$TERMUX_PKG_MAKE_PROCESSES"
}

termux_step_make_install() {
    make install
}

termux_step_post_make_install() {
    local PG_SHARE_DIR="$TERMUX_PREFIX/share/postgresql/extension"
    local PG_LIB_DIR="$TERMUX_PREFIX/lib/postgresql"

    # 确保文件安装到正确的 PostgreSQL 扩展目录
    mkdir -p "$PG_SHARE_DIR" "$PG_LIB_DIR"

    if [ -f "$TERMUX_PREFIX/share/extension/vector.control" ]; then
        cp "$TERMUX_PREFIX/share/extension/vector--"*.sql "$PG_SHARE_DIR/" 2>/dev/null || true
        cp "$TERMUX_PREFIX/share/extension/vector.control" "$PG_SHARE_DIR/"
    fi

    if [ -f "$TERMUX_PREFIX/lib/vector.so" ]; then
        cp "$TERMUX_PREFIX/lib/vector.so" "$PG_LIB_DIR/"
    fi
}







