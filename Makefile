.DEFAULT_GOAL := all
INITIAL_VIEWS ?= 4
AUTOTOUR ?= 0
PROFILE ?= 0
VALIDATE ?= 0
N64_INST ?= $(CURDIR)/.build/libdragon

ROM := n64-3d-splitscreen
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
.PHONY: all test clean FORCE models

OBJS := $(BUILD_DIR)/main.o $(BUILD_DIR)/scene.o

$(BUILD_DIR)/$(ROM).elf: $(OBJS)

$(ROM).z64: N64_ROM_TITLE = "BUNNY MEADOW"
$(ROM).z64: N64_ROM_REGIONFREE = true
$(ROM).z64: N64_ROM_SAVETYPE = none
$(ROM).z64: N64_ROM_CONTROLLER1 = n64
$(ROM).z64: N64_ROM_CONTROLLER2 = n64
$(ROM).z64: N64_ROM_CONTROLLER3 = n64
$(ROM).z64: N64_ROM_CONTROLLER4 = n64

CFLAGS += -DINITIAL_VIEWS=$(INITIAL_VIEWS) -DAUTOTOUR=$(AUTOTOUR) -DPROFILE=$(PROFILE)

$(BUILD_DIR)/settings: FORCE
	@mkdir -p $(BUILD_DIR)
	@echo '$(INITIAL_VIEWS) $(AUTOTOUR) $(PROFILE) $(VALIDATE)' > $@.tmp
	@cmp -s $@.tmp $@ || mv $@.tmp $@
	@rm -f $@.tmp

$(BUILD_DIR)/main.o: $(BUILD_DIR)/settings Makefile

ifeq ($(VALIDATE),1)
CFLAGS += -DRDPQ_VALIDATE
endif

$(BUILD_DIR)/scene.o: src/scene.zig src/game.zig src/generated/rabbit.zig tools/patch_mips_abi.zig scripts/verify-zig-abi.sh Makefile
	@mkdir -p $(dir $@)
	@echo "    [ZIG] $<"
	zig build-obj $< -target mips64-freestanding-gnuabin32 -mcpu mips3+noabicalls -fno-PIC \
		-O ReleaseSmall -fno-stack-check -femit-bin=$@
	zig run tools/patch_mips_abi.zig -- $@
	$(N64_OBJCOPY) --rename-section .mdebug.abiN32=.mdebug.abiO64 $@
	./scripts/verify-zig-abi.sh $@

test:
	zig test src/scene.zig

models:
	"$${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}" --background --python scripts/make-rabbit.py

clean:
	$(RM) -r $(BUILD_DIR) $(ROM).z64

-include $(wildcard $(BUILD_DIR)/*.d)
