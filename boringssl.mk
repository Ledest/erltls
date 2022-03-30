REBAR_DEPS_DIR ?= $(CURDIR)/_build/default/lib

boringssl: libssl libcrypto

$(REBAR_DEPS_DIR)/boringssl/build/:
	mkdir $(REBAR_DEPS_DIR)/boringssl/build

$(REBAR_DEPS_DIR)/boringssl/lib/:
	mkdir $(REBAR_DEPS_DIR)/boringssl/lib

$(REBAR_DEPS_DIR)/boringssl/build/Makefile: $(REBAR_DEPS_DIR)/boringssl/build/
	cmake -S $(REBAR_DEPS_DIR)/boringssl -B $(REBAR_DEPS_DIR)/boringssl/build \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-fPIC" -DCMAKE_CXX_FLAGS="-fPIC"

libssl: $(REBAR_DEPS_DIR)/boringssl/build/Makefile
	$(MAKE) -C $(REBAR_DEPS_DIR)/boringssl/build -j8 ssl

libcrypto: $(REBAR_DEPS_DIR)/boringssl/build/Makefile
	$(MAKE) -C $(REBAR_DEPS_DIR)/boringssl/build -j8 crypto
