ROM := n64-2048
BUILD_DIR := build
SOURCE_DIR := src

ifeq ($(N64_INST),)
  $(error N64_INST is not set; run through mise or export it explicitly)
endif
ifeq ($(wildcard $(N64_INST)/include/n64.mk),)
  $(error libdragon is not installed at $(N64_INST); run `mise run setup`)
endif

include $(N64_INST)/include/n64.mk

all: $(ROM).z64
.PHONY: all test clean

OBJS := $(BUILD_DIR)/main.o $(BUILD_DIR)/game.o

$(BUILD_DIR)/$(ROM).elf: $(OBJS)

$(ROM).z64: N64_ROM_TITLE = "2048"
$(ROM).z64: N64_ROM_REGIONFREE = true
$(ROM).z64: N64_ROM_CONTROLLER1 = n64

$(BUILD_DIR)/game.o: src/game.zig tools/patch_mips_abi.zig
	@mkdir -p $(dir $@)
	@echo "    [ZIG] $<"
	zig build-obj $< -target mips64-freestanding-gnuabin32 -mcpu mips3 \
		-O ReleaseSmall -fno-stack-check -femit-bin=$@
	zig run tools/patch_mips_abi.zig -- $@
	$(N64_OBJCOPY) --redefine-sym memset=zig_memset_impl \
		--rename-section .mdebug.abiN32=.mdebug.abiO64 $@

test:
	zig test src/game.zig

clean:
	$(RM) -r $(BUILD_DIR) $(ROM).z64

-include $(wildcard $(BUILD_DIR)/*.d)
