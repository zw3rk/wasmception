# Any copyright is dedicated to the Public Domain.
# http://creativecommons.org/publicdomain/zero/1.0/

ROOT_DIR=${CURDIR}
LLVM_REV=344317
CLANG_REV=344318
LLD_REV=344318
MUSL_SHA=6489af63b184d21691c2b915ad64adc8bd147fc7 #edeb5004e6e016e326c475ce53199755d76d103f
COMPILER_RT_REV=344320
LIBCXX_REV=344320
LIBCXXABI_REV=344320


VERSION=0.1
DEBUG_PREFIX_MAP=-fdebug-prefix-map=$(ROOT_DIR)=wasmception://v$(VERSION)

default: build
	echo "Use --sysroot=$(ROOT_DIR)/sysroot -fdebug-prefix-map=$(ROOT_DIR)=wasmception://v$(VERSION)"

clean:
	rm -rf build src dist sysroot wasmception-*-bin.tar.gz

src/llvm.CLONED:
	mkdir -p src/
	cd src/; svn co http://llvm.org/svn/llvm-project/llvm/trunk llvm
	cd src/llvm/tools; svn co http://llvm.org/svn/llvm-project/cfe/trunk clang
	cd src/llvm/tools; svn co http://llvm.org/svn/llvm-project/lld/trunk lld
ifdef LLVM_REV
	cd src/llvm; svn up -r$(LLVM_REV)
endif
ifdef CLANG_REV
	cd src/llvm/tools/clang; svn up -r$(CLANG_REV)
endif
ifdef LLD_REV
	cd src/llvm/tools/lld; svn up -r$(LLD_REV)
endif
	touch src/llvm.CLONED

src/musl.CLONED:
	mkdir -p src/
	cd src/; git clone https://github.com/WebGHC/musl.git # https://github.com/jfbastien/musl.git
ifdef MUSL_SHA
	cd src/musl; git checkout $(MUSL_SHA)
endif
	cd src/musl; patch -p 1 < $(ROOT_DIR)/patches/musl.1.patch
#	cd src/musl; patch -p 1 < $(ROOT_DIR)/patches/musl.2.patch
	touch src/musl.CLONED

src/compiler-rt.CLONED:
	mkdir -p src/
	cd src/; svn co http://llvm.org/svn/llvm-project/compiler-rt/trunk compiler-rt
ifdef COMPILER_RT_REV
	cd src/compiler-rt; svn up -r$(COMPILER_RT_REV)
endif
	touch src/compiler-rt.CLONED

src/libcxx.CLONED:
	mkdir -p src/
	cd src/; svn co http://llvm.org/svn/llvm-project/libcxx/trunk libcxx
ifdef LIBCXX_REV
	cd src/libcxx; svn up -r$(LIBCXX_REV)
endif
	touch src/libcxx.CLONED

src/libcxxabi.CLONED:
	mkdir -p src/
	cd src/; svn co http://llvm.org/svn/llvm-project/libcxxabi/trunk libcxxabi
ifdef LIBCXXABI_REV
	cd src/libcxxabi; svn up -r$(LIBCXXABI_REV)
endif
	touch src/libcxxabi.CLONED

build/llvm.BUILT: src/llvm.CLONED
	mkdir -p build/llvm
	cd build/llvm; cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX=$(ROOT_DIR)/dist \
		-DLLVM_TARGETS_TO_BUILD= \
		-DLLVM_ENABLE_FFI=ON \
		-DLLVM_ENABLE_RTTI=ON \
		-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly \
		$(ROOT_DIR)/src/llvm
	cd build/llvm; $(MAKE) -j 8 \
		install-clang \
		install-lld \
		install-llc \
		install-llvm-ar \
		install-llvm-dis \
		install-llvm-nm \
		install-llvm-ranlib \
		install-llvm-dwarfdump \
                install-llvm-objdump \
		llvm-config
	touch build/llvm.BUILT

build/musl.BUILT: src/musl.CLONED build/llvm.BUILT
	mkdir -p build/musl
	cd build/musl; $(ROOT_DIR)/src/musl/configure \
		CC=$(ROOT_DIR)/dist/bin/clang \
		CFLAGS="--target=wasm32-unknown-unknown-wasm -O3 $(DEBUG_PREFIX_MAP)" \
		--prefix=$(ROOT_DIR)/sysroot \
		--enable-debug \
		wasm32
	make -C build/musl -j 8 install CROSS_COMPILE=$(ROOT_DIR)/dist/bin/llvm-
	cp src/musl/arch/wasm32/wasm.syms sysroot/lib/libc.imports
	touch build/musl.BUILT

build/compiler-rt.BUILT: src/compiler-rt.CLONED build/llvm.BUILT
	mkdir -p build/compiler-rt
	cd build/compiler-rt; cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DCOMPILER_RT_BAREMETAL_BUILD=On \
		-DCOMPILER_RT_BUILD_XRAY=OFF \
		-DCOMPILER_RT_INCLUDE_TESTS=OFF \
		-DCOMPILER_RT_ENABLE_IOS=OFF \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=On \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm -O1 $(DEBUG_PREFIX_MAP)" \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCOMPILER_RT_OS_DIR=. \
		-DCMAKE_INSTALL_PREFIX=$(ROOT_DIR)/dist/lib/clang/8.0.0/ \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		$(ROOT_DIR)/src/compiler-rt/lib/builtins
	cd build/compiler-rt; make -j 8 install
	cp -R $(ROOT_DIR)/build/llvm/lib/clang $(ROOT_DIR)/dist/lib/
	touch build/compiler-rt.BUILT

build/libcxx.BUILT: build/llvm.BUILT src/libcxx.CLONED build/compiler-rt.BUILT build/musl.BUILT
	mkdir -p build/libcxx
	cd build/libcxx; cmake -G "Unix Makefiles" \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		-DLIBCXX_ENABLE_THREADS:BOOL=OFF \
		-DLIBCXX_ENABLE_STDIN:BOOL=OFF \
		-DLIBCXX_ENABLE_STDOUT:BOOL=OFF \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXX_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY:BOOL=OFF \
		-DLIBCXX_ENABLE_FILESYSTEM:BOOL=OFF \
		-DLIBCXX_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXX_ENABLE_RTTI:BOOL=OFF \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXX_CXX_ABI_INCLUDE_PATHS=$(ROOT_DIR)/src/libcxxabi/include \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP)" \
		-DCMAKE_CXX_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP) -D_LIBCPP_HAS_MUSL_LIBC" \
		--debug-trycompile \
		$(ROOT_DIR)/src/libcxx
	cd build/libcxx; make -j 8 install
	touch build/libcxx.BUILT

build/libcxxabi.BUILT: src/libcxxabi.CLONED build/libcxx.BUILT build/llvm.BUILT
	mkdir -p build/libcxxabi
	cd build/libcxxabi; cmake -G "Unix Makefiles" \
		-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
		-DCMAKE_CXX_COMPILER_WORKS=ON \
		-DCMAKE_C_COMPILER_WORKS=ON \
		-DLIBCXXABI_ENABLE_EXCEPTIONS:BOOL=OFF \
		-DLIBCXXABI_ENABLE_SHARED:BOOL=OFF \
		-DLIBCXXABI_ENABLE_THREADS:BOOL=OFF \
		-DCXX_SUPPORTS_CXX11=ON \
		-DLLVM_COMPILER_CHECKED=ON \
		-DCMAKE_BUILD_TYPE=RelWithDebugInfo \
		-DLIBCXXABI_LIBCXX_PATH=$(ROOT_DIR)/src/libcxx \
		-DLIBCXXABI_LIBCXX_INCLUDES=$(ROOT_DIR)/sysroot/include/c++/v1 \
		-DLLVM_CONFIG_PATH=$(ROOT_DIR)/build/llvm/bin/llvm-config \
		-DCMAKE_TOOLCHAIN_FILE=$(ROOT_DIR)/wasm_standalone.cmake \
		-DCMAKE_C_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP)" \
		-DCMAKE_CXX_FLAGS="--target=wasm32-unknown-unknown-wasm $(DEBUG_PREFIX_MAP) -D_LIBCPP_HAS_MUSL_LIBC" \
		-DUNIX:BOOL=ON \
		--debug-trycompile \
		$(ROOT_DIR)/src/libcxxabi
	cd build/libcxxabi; make -j 8 install
	touch build/libcxxabi.BUILT

BASICS=sysroot/include/wasmception.h sysroot/lib/wasmception.wasm

sysroot/include/wasmception.h: basics/wasmception.h
	cp basics/wasmception.h sysroot/include/

sysroot/lib/wasmception.wasm: build/llvm.BUILT basics/wasmception.c
	dist/bin/clang \
		--target=wasm32-unknown-unknown-wasm \
		--sysroot=./sysroot basics/wasmception.c \
		-c -O3 -g $(DEBUG_PREFIX_MAP) \
		-o sysroot/lib/wasmception.wasm

build: build/llvm.BUILT build/musl.BUILT build/compiler-rt.BUILT $(BASICS)

strip: build/llvm.BUILT
	cd dist/bin; strip clang-8 llc lld llvm-ar

collect-sources:
	-rm -rf build/sources build/sources.txt
	{ find sysroot -name "*.o"; find sysroot -name "*.wasm"; find dist/lib sysroot -name "lib*.a"; } | \
	  xargs ./list_debug_sources.py | sort > build/sources.txt
	echo "sysroot/include" >> build/sources.txt
	for f in $$(cat build/sources.txt); \
	  do mkdir -p `dirname build/sources/$$f`; cp -R $$f `dirname build/sources/$$f`; done;
	cd build/sources && { git init; git checkout --orphan v$(VERSION); git add -A .; git commit -m "Sources"; }
	echo "cd build/sources && git push -f git@github.com:yurydelendik/wasmception.git v$(VERSION)"

revisions:
	cd src/llvm; echo "LLVM_REV=`svn info --show-item revision`"
	cd src/llvm/tools/clang; echo "CLANG_REV=`svn info --show-item revision`"
	cd src/llvm/tools/lld; echo "LLD_REV=`svn info --show-item revision`"
	cd src/musl; echo "MUSL_SHA=`git log -1 --format="%H"`"
	cd src/compiler-rt; echo "COMPILER_RT_REV=`svn info --show-item revision`"
	cd src/libcxx; echo "LIBCXX_REV=`svn info --show-item revision`"
	cd src/libcxxabi; echo "LIBCXXABI_REV=`svn info --show-item revision`"

OS_NAME=$(shell uname -s | tr '[:upper:]' '[:lower:]')
pack:
	tar czf wasmception-${OS_NAME}-bin.tar.gz dist sysroot

.PHONY: default clean build strip revisions pack collect-sources
