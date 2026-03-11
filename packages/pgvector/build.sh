TERMUX_PKG_HOMEPAGE="https://github.com/pgvector/pgvector"
TERMUX_PKG_DESCRIPTION="Open-source vector similarity search for PostgreSQL"
TERMUX_PKG_LICENSE="PostgreSQL"
TERMUX_PKG_MAINTAINER="Julius"
TERMUX_PKG_VERSION="0.8.0"

TERMUX_PKG_SRCURL="https://github.com/pgvector/pgvector/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="867a2c328d4928a5a9d6f052cd3bc78c7d60228a9b914ad32aa3db88e9de27b0"
TERMUX_PKG_DEPENDS="postgresql"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
    export PG_CONFIG="$TERMUX_PREFIX/bin/pg_config"
    # 关键：告诉 pgxs 不要尝试运行测试
    export NO_INSTALLCHECK=1
    # 关键：清空 TESTS 变量，防止 pgxs.mk 生成测试相关的依赖
    # 这样即使有人运行 make check，也会因为没测试可做而直接跳过或失败（但我们不会运行它）
    # 注意：我们不能在这里直接修改 Makefile，但可以通过环境变量影响某些行为
}

termux_step_make() {
    # 【关键】
    # 1. 只明确构建 'all' 目标。
    # 2. 设置 OPTFLAGS="" 以避免 -march=native 在交叉编译环境中可能产生的问题。
    # 3. 绝对不运行 'make check' 或 'make installcheck'。
    make OPTFLAGS="" -j "$TERMUX_PKG_MAKE_PROCESSES" all
}

termux_step_make_install() {
    # 【关键】
    # 放弃使用 'make install'。
    # 因为 'make install' 依赖于 pgxs.mk 的规则，虽然它本身不跑测试，
    # 但为了 100% 避免任何潜在的副作用（如某些 hook），我们手动复制。

    local PG_SHARE_DIR="$TERMUX_PREFIX/share/postgresql/extension"
    local PG_LIB_DIR="$TERMUX_PREFIX/lib/postgresql"

    mkdir -p "$PG_SHARE_DIR" "$PG_LIB_DIR"

    echo ">>> Manually installing pgvector files..."

    # 1. 复制 .so 库文件
    if [ -f "vector.so" ]; then
        cp "vector.so" "$PG_LIB_DIR/"
        echo "✓ Copied vector.so to $PG_LIB_DIR/"
    else
        termux_error_exit "ERROR: vector.so not found! Build failed."
    fi

    # 2. 复制 Control 文件
    if [ -f "sql/vector.control" ]; then
        cp "sql/vector.control" "$PG_SHARE_DIR/"
        echo "✓ Copied vector.control to $PG_SHARE_DIR/"
    else
        termux_error_exit "ERROR: vector.control not found!"
    fi

    # 3. 复制 SQL 文件 (包括生成的 versioned 文件)
    # make all 已经生成了 sql/vector--0.8.0.sql
    if ls sql/vector--*.sql 1> /dev/null 2>&1; then
        cp sql/vector--*.sql "$PG_SHARE_DIR/"
        echo "✓ Copied SQL files to $PG_SHARE_DIR/"
    else
        termux_error_exit "ERROR: No versioned SQL files found!"
    fi

    echo ">>> Manual installation complete. Zero tests executed."
}

termux_step_create_debscripts() {
    cat <<- EOF > ./postinst
    #!$TERMUX_PREFIX/bin/bash
    echo "pgvector v${TERMUX_PKG_VERSION} installed successfully!"
    echo "To enable: psql -d <dbname> -c 'CREATE EXTENSION vector;'"
    EOF
    chmod 0755 ./postinst
}