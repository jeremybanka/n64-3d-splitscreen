.DEFAULT_GOAL := all
INITIAL_VIEWS ?= 4
AUTOTOUR ?= 0
PROFILE ?= 0
VALIDATE ?= 0
BENCHMARK ?= 0
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
TINY3D_DIR ?= $(CURDIR)/.build/tiny3d
ifeq ($(wildcard $(TINY3D_DIR)/t3d.mk),)
  $(error Tiny3D is not installed; run `mise run setup` or `./scripts/bootstrap-tiny3d.sh`)
endif
include $(TINY3D_DIR)/t3d.mk
# Link it as an explicit prerequisite so rebuilding the library relinks the ROM.
N64_LDFLAGS := $(filter-out %/libt3d.a,$(N64_LDFLAGS))

$(TINY3D_DIR)/build/libt3d.a:
	$(MAKE) -C $(TINY3D_DIR)


all: $(ROM).z64
.PHONY: all test clean FORCE models

OBJS := $(BUILD_DIR)/main.o $(BUILD_DIR)/scene.o

$(BUILD_DIR)/$(ROM).elf: $(OBJS) $(TINY3D_DIR)/build/libt3d.a

$(ROM).z64: N64_ROM_TITLE = "BUNNY MEADOW"
$(ROM).z64: N64_ROM_REGIONFREE = true
$(ROM).z64: N64_ROM_SAVETYPE = none
$(ROM).z64: N64_ROM_CONTROLLER1 = n64
$(ROM).z64: N64_ROM_CONTROLLER2 = n64
$(ROM).z64: N64_ROM_CONTROLLER3 = n64
$(ROM).z64: N64_ROM_CONTROLLER4 = n64

CFLAGS += -DINITIAL_VIEWS=$(INITIAL_VIEWS) -DAUTOTOUR=$(AUTOTOUR) -DPROFILE=$(PROFILE) -DBENCHMARK=$(BENCHMARK)

$(BUILD_DIR)/settings: FORCE
	@mkdir -p $(BUILD_DIR)
	@echo '$(INITIAL_VIEWS) $(AUTOTOUR) $(PROFILE) $(VALIDATE) $(BENCHMARK)' > $@.tmp
	@cmp -s $@.tmp $@ || mv $@.tmp $@
	@rm -f $@.tmp

$(BUILD_DIR)/main.o: $(BUILD_DIR)/settings Makefile

ifeq ($(VALIDATE),1)
CFLAGS += -DRDPQ_VALIDATE
endif

# Let Zig discover every import and @embedFile through its own cache, including
# newly added modules. Only replace the patched object when its bytes change,
# so a cache hit does not relink/repackage the ROM.
$(BUILD_DIR)/scene.o: src/scene.zig FORCE
	@mkdir -p $(dir $@)
	@echo "    [ZIG] $<"
	zig build-obj $< -target mips64-freestanding-gnuabin32 -mcpu mips3+noabicalls -fno-PIC \
		-O ReleaseSmall -fno-stack-check -femit-bin=$@.tmp
	zig run tools/patch_mips_abi.zig -- $@.tmp
	$(N64_OBJCOPY) --rename-section .mdebug.abiN32=.mdebug.abiO64 $@.tmp
	./scripts/verify-zig-abi.sh $@.tmp
	@cmp -s $@.tmp $@ || mv $@.tmp $@
	@rm -f $@.tmp

test:
	zig test src/scene.zig

models:
	"$${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}" --background --python scripts/make-rabbit.py

clean:
	$(RM) -r $(BUILD_DIR) $(ROM).z64

-include $(wildcard $(BUILD_DIR)/*.d)
