TERMUX_PKG_HOMEPAGE="https://github.com/pgvector/pgvector"
TERMUX_PKG_DESCRIPTION="Open-source vector similarity search for PostgreSQL"
TERMUX_PKG_LICENSE="PostgreSQL"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="Julius"
TERMUX_PKG_VERSION="0.8.0"

TERMUX_PKG_SRCURL="https://github.com/pgvector/pgvector/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="867a2c328d4928a5a9d6f052cd3bc78c7d60228a9b914ad32aa3db88e9de27b0"
TERMUX_PKG_DEPENDS="postgresql"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
    export PG_CONFIG="$TERMUX_PREFIX/bin/pg_config"
    # 获取必要的编译标志
    # 注意：我们只取 CFLAGS，不取 LDFLAGS 中可能包含的奇怪路径
    export PG_CFLAGS=$($PG_CONFIG --cflags)
    # 移除可能存在的 -march=native (虽然我们在下面会覆盖，但以防万一)
    export PG_CFLAGS=$(echo $PG_CFLAGS | sed 's/-march=[^ ]*//g')

    # 添加我们自己的优化标志 (替代 OPTFLAGS)
    # -O2 是安全且高效的，-ftree-vectorize 开启自动向量化
    export EXTRA_CFLAGS="-O2 -ftree-vectorize -fassociative-math -fno-signed-zeros -fno-trapping-math -fPIC"

    echo "PG_CFLAGS: $PG_CFLAGS"
    echo "EXTRA_CFLAGS: $EXTRA_CFLAGS"
}

termux_step_make() {
    echo ">>> Starting manual compilation..."

    # 1. 创建对象文件列表
    # 对应 Makefile 中的 OBJS 变量
    local OBJS="src/bitutils.o src/bitvec.o src/halfutils.o src/halfvec.o src/hnsw.o src/hnswbuild.o src/hnswinsert.o src/hnswscan.o src/hnswutils.o src/hnswvacuum.o src/ivfbuild.o src/ivfflat.o src/ivfinsert.o src/ivfkmeans.o src/ivfscan.o src/ivfutils.o src/ivfvacuum.o src/sparsevec.o src/vector.o"

    # 2. 编译每个 .c 文件为 .o 文件
    for src in src/*.c; do
        obj="${src%.c}.o"
        echo "Compiling $src -> $obj"
        # 直接使用 gcc，避开 make/pgxs 的复杂逻辑
        if ! $CC $PG_CFLAGS $EXTRA_CFLAGS -I$TERMUX_PREFIX/include/postgresql/server -I$TERMUX_PREFIX/include -c "$src" -o "$obj"; then
            termux_error_exit "Failed to compile $src"
        fi
    done

    echo ">>> Compilation of .o files complete."

    # 3. 手动链接生成 vector.so
    echo "Linking vector.so..."
    # 获取链接库路径
    local PG_LIBS=$($PG_CONFIG --ldflags)
    local PG_LIBS_SHARED=$($PG_CONFIG --ldflags-sl) # 专门用于共享库的标志

    # 构建链接命令
    # 注意：-shared 是关键，-L 指定库路径，-lpostgres 或其他需要的库
    # pgvector 通常只需要链接 postgres 的一些基础符号，这些通常在加载时由 postgres 解析
    # 但为了保险，我们链接 libpq 或者 postgres 的核心库如果必要的话。
    # 实际上，Postgres 扩展通常不需要显式链接 libpostgres，只需要 -L 路径正确即可。
    # 这里的重点是不要触发任何需要运行二进制文件的步骤。

    if ! $CC -shared -o vector.so $OBJS $PG_LIBS $PG_LIBS_SHARED -L$TERMUX_PREFIX/lib -L$TERMUX_PREFIX/lib/postgresql -lm; then
        termux_error_exit "Failed to link vector.so"
    fi

    echo "✓ vector.so created successfully!"
    ls -lh vector.so

    # 4. 生成 versioned SQL 文件 (对应 Makefile 中的 all 目标的另一部分)
    echo "Generating versioned SQL file..."
    cp sql/vector.sql sql/vector--${TERMUX_PKG_VERSION}.sql
}

termux_step_make_install() {
    local PG_SHARE_DIR="$TERMUX_PREFIX/share/postgresql/extension"
    local PG_LIB_DIR="$TERMUX_PREFIX/lib/postgresql"

    mkdir -p "$PG_SHARE_DIR" "$PG_LIB_DIR"

    echo ">>> Manually installing pgvector files..."

    if [ -f "vector.so" ]; then
        cp "vector.so" "$PG_LIB_DIR/"
        echo "✓ Copied vector.so"
    else
        termux_error_exit "ERROR: vector.so not found!"
    fi

    if [ -f "vector.control" ]; then
        cp "vector.control" "$PG_SHARE_DIR/"
        echo "✓ Copied vector.control"
    else
        termux_error_exit "ERROR: vector.control not found!"
    fi

    if ls sql/vector--*.sql 1> /dev/null 2>&1; then
        cp sql/vector--*.sql "$PG_SHARE_DIR/"
        echo "✓ Copied SQL files"
    else
        termux_error_exit "ERROR: No versioned SQL files found!"
    fi

    echo ">>> Installation complete."
}

termux_step_create_debscripts() {
    cat > ./postinst <<EOF
#!/data/data/com.xpmall/files/usr/bin/bash
echo "pgvector v${TERMUX_PKG_VERSION} installed successfully!"
echo "To enable: psql -d <dbname> -c 'CREATE EXTENSION vector;'"
EOF
    chmod 0755 ./postinst
}