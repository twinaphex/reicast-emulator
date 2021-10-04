DEBUG         := 0
DEBUG_ASAN    := 0
DEBUG_UBSAN   := 0
NO_REND       := 0
HAVE_GL       := 1
HAVE_GL2      := 0
HAVE_OIT      ?= 0
HAVE_VULKAN   := 0
HAVE_CORE     := 0
NO_THREADS    := 0
NO_EXCEPTIONS := 0
NO_NVMEM      := 0
NO_VERIFY     := 1
HAVE_LTCG     ?= 0
HAVE_GENERIC_JIT := 1
HAVE_GL3      := 0
FORCE_GLES    := 0
STATIC_LINKING:= 0
HAVE_TEXUPSCALE := 1
HAVE_OPENMP   := 1
HAVE_CHD      := 1
HAVE_CLANG    ?= 0
HAVE_CDROM    := 0
ENABLE_MODEM  := 1

TARGET_NAME   := flycast

ifeq ($(HAVE_CLANG),1)
	CXX      = ${CC_PREFIX}clang++
	CC       = ${CC_PREFIX}clang
	SHARED   := -fuse-ld=lld
else
	CXX      ?= ${CC_PREFIX}g++
	CC       ?= ${CC_PREFIX}gcc
	SHARED   :=
endif
ifeq ($(HAVE_LTCG),1)
	SHARED   += -flto
endif

ifneq (${AS},)
	CC_AS := ${AS}
endif
CC_AS    ?= ${CC_PREFIX}as

MFLAGS   := 
ASFLAGS  := 
LDFLAGS  :=
LDFLAGS_END :=
INCFLAGS :=
LIBS     :=
CFLAGS   := 
CXXFLAGS :=

GIT_VERSION := " $(shell git rev-parse --short HEAD || echo unknown)"
ifneq ($(GIT_VERSION)," unknown")
	CXXFLAGS += -DGIT_VERSION=\"$(GIT_VERSION)\"
endif

UNAME=$(shell uname -a)

LIBRETRO_DIR := .

# Cross compile ?

ifeq (,$(ARCH))
	ARCH = $(shell uname -m)
endif

# Target Dynarec
WITH_DYNAREC = $(ARCH)

ifeq ($(ARCH), $(filter $(ARCH), i386 i686))
	WITH_DYNAREC = x86
endif

ifeq ($(platform),)
	platform = unix
	ifeq ($(UNAME),)
		platform = win
	else ifneq ($(findstring MINGW,$(UNAME)),)
		platform = win
	else ifneq ($(findstring Darwin,$(UNAME)),)
		platform = osx
	else ifneq ($(findstring win,$(UNAME)),)
		platform = win
	endif
endif

# system platform
system_platform = unix
ifeq ($(shell uname -a),)
	EXE_EXT = .exe
	system_platform = win
else ifneq ($(findstring Darwin,$(shell uname -a)),)
	system_platform = osx
	arch = intel
	ifeq ($(shell uname -p),powerpc)
		arch = ppc
	endif
else ifneq ($(findstring MINGW,$(shell uname -a)),)
	system_platform = win
endif

CORE_DIR := .

DYNAREC_USED = 0
CORE_DEFINES   := -D__LIBRETRO__  -DHAVE_GLSYM_PRIVATE

ifeq ($(NO_VERIFY),1)
	CORE_DEFINES += -DNO_VERIFY
endif

DC_PLATFORM=dreamcast

HOST_CPU_X86=0x20000001
HOST_CPU_ARM=0x20000002
HOST_CPU_MIPS=0x20000003
HOST_CPU_X64=0x20000004
HOST_CPU_ARM64=0x20000006

ifeq ($(STATIC_LINKING),1)
	EXT=a
endif

# Unix
ifneq (,$(findstring unix,$(platform)))
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	LDFLAGS +=  -Wl,--no-undefined
	ifneq (,$(findstring Haiku,$(shell uname -s)))
		LIBS += -lroot -lnetwork
	else
		LIBS += -lrt
		HAVE_VULKAN = 1
	endif

	ifneq ($(HAVE_GL2), 1)
		ifneq ($(HAVE_OIT), 1)
			HAVE_GL3 = 1
		endif
	endif

	HAVE_CDROM = 1
	fpic = -fPIC

	ifeq ($(WITH_DYNAREC), $(filter $(WITH_DYNAREC), x86_64 x64))
		CFLAGS += -DTARGET_LINUX_x64
		SINGLE_PREC_FLAGS=1
		HAVE_GENERIC_JIT = 0
	else ifeq ($(WITH_DYNAREC), x86)
		CFLAGS += -m32 -D TARGET_LINUX_x86 -D TARGET_NO_AREC
		SINGLE_PREC_FLAGS=1
		MFLAGS += -m32
		ASFLAGS += --32
		LDFLAGS += -m32
		HAVE_GENERIC_JIT = 0
	endif
	PLATFORM_EXT := unix

# Raspberry Pi
else ifneq (,$(findstring rpi,$(platform)))
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	SINGLE_PREC_FLAGS = 1
	PLATFORM_EXT := unix
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0
	
	ifneq (,$(findstring rpi4,$(platform)))
		FORCE_GLES = 1
		ifneq (,$(findstring rpi4_64,$(platform)))
			# 64-bit userspace
			ARM_FLOAT_ABI_HARD = 0
			CPUFLAGS += -DTARGET_LINUX_ARMv8 -frename-registers
			CFLAGS += -march=armv8-a+crc -mcpu=cortex-a72 -mtune=cortex-a72 $(CPUFLAGS)
			CXXFLAGS += -march=armv8-a+crc -mcpu=cortex-a72 -mtune=cortex-a72 $(CPUFLAGS)
			ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
			WITH_DYNAREC=arm64
		else
			# rpi4 flags are taken from rockpro64
			CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
			# as of 2020-05-07, the following workaround doesn't seem required
			# CORE_DEFINES += -DRPI4_SET_UNIFORM_ATTRIBUTES_BUG
			CFLAGS += -marm -mfloat-abi=hard -mcpu=cortex-a72 -mtune=cortex-a72 -mfpu=neon-vfpv4 $(CPUFLAGS)
			CXXFLAGS += -marm -mfloat-abi=hard -mcpu=cortex-a72 -mtune=cortex-a72 -mfpu=neon-vfpv4 $(CPUFLAGS)
			ifeq ($(HAVE_CLANG),0)
				CFLAGS += -mvectorize-with-neon-quad
				CXXFLAGS += -mvectorize-with-neon-quad
			endif
			ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
		endif
	else ifneq (,$(findstring rpi3,$(platform)))
			FORCE_GLES = 1
			ifneq (,$(findstring rpi3_64,$(platform)))
				# 64-bit userspace
				ARM_FLOAT_ABI_HARD = 0
				CPUFLAGS += -DTARGET_LINUX_ARMv8 -frename-registers
				CFLAGS += -march=armv8-a+crc -mcpu=cortex-a53 -mtune=cortex-a53 $(CPUFLAGS)
				CXXFLAGS += -march=armv8-a+crc -mcpu=cortex-a53 -mtune=cortex-a53 $(CPUFLAGS)
				ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
				WITH_DYNAREC=arm64
			else
				CFLAGS += -mtune=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard
				CXXFLAGS += -mtune=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard
			endif
	else
		ifeq (,$(findstring mesa,$(platform)))
			GLES = 1
			GL_LIB := -L/opt/vc/lib -lbrcmGLESv2
			INCFLAGS += -I/opt/vc/include
			CFLAGS += -DTARGET_NO_STENCIL
		else
			FORCE_GLES = 1
		endif
		ifneq (,$(findstring rpi2,$(platform)))
			CFLAGS += -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
			CXXFLAGS += -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
		endif
		CORE_DEFINES += -DLOW_END
	endif

# Classic Platforms #####################
# Platform affix = classic_<ISA>_<µARCH>
#########################################
# (armv7 a7, hard point, neon based) ####
# NESC, SNESC, C64 mini 
else ifeq ($(platform), classic_armv7_a7)
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	HAVE_LTCG = 0
	HAVE_OPENMP = 1
	CFLAGS += -Ofast \
	-flto=4 -fwhole-program -fuse-linker-plugin \
	-fdata-sections -ffunction-sections -Wl,--gc-sections \
	-fno-stack-protector -fno-ident -fomit-frame-pointer \
	-falign-functions=1 -falign-jumps=1 -falign-loops=1 \
	-fno-unwind-tables -fno-asynchronous-unwind-tables -fno-unroll-loops \
	-fmerge-all-constants -fno-math-errno \
	-marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
	CXXFLAGS += $(CFLAGS)
	ASFLAGS += $(CFLAGS)
	LDFLAGS += -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
	ifeq ($(shell echo `$(CC) -dumpversion` "< 4.9" | bc -l), 1)
		CFLAGS += -march=armv7-a
		LDFLAGS += -march=armv7-a
	else
		CFLAGS += -march=armv7ve
		LDFLAGS += -march=armv7ve
		# If gcc is 5.0 or later
		ifeq ($(shell echo `$(CC) -dumpversion` ">= 5" | bc -l), 1)
			LDFLAGS += -static-libgcc -static-libstdc++
		endif
	endif
	PLATFORM_EXT := unix
	WITH_DYNAREC = arm
	HAVE_GENERIC_JIT = 0
	CORE_DEFINES += -DLOW_END -DLOW_RES
#########################################
# (armv8 a35, hard point, neon based) ###
# PlayStation Classic
else ifeq ($(platform), classic_armv8_a35)
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	HAVE_LTCG = 0
	HAVE_OPENMP = 0
	CFLAGS += -Ofast \
	-fuse-linker-plugin \
	-fno-stack-protector -fno-ident -fomit-frame-pointer \
	-fmerge-all-constants -ffast-math -funroll-all-loops \
	-marm -mcpu=cortex-a35 -mfpu=neon-fp-armv8 -mfloat-abi=hard
	CXXFLAGS += $(CFLAGS)
	ASFLAGS += $(CFLAGS)
	LDFLAGS += -marm -mcpu=cortex-a35 -mfpu=neon-fp-armv8 -mfloat-abi=hard -Ofast -flto -fuse-linker-plugin
	PLATFORM_EXT := unix
	WITH_DYNAREC = arm
	HAVE_GENERIC_JIT = 0
	CORE_DEFINES += -DLOW_END -DLOW_RES
	
#########################################

# sun8i Allwinner H2+ / H3 for mainline Builds
# like Orange PI, Nano PI, Banana PI, Tritium, Sunvell R69, AlphaCore2
# by MPCORE-HUB/Liontek1985

else ifeq ($(platform), sun8i)
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
	CFLAGS += -marm -mfloat-abi=hard -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard $(CPUFLAGS)
	CXXFLAGS += -marm -mfloat-abi=hard -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard $(CPUFLAGS)
	ifeq ($(HAVE_CLANG),0)
		CFLAGS += -mvectorize-with-neon-quad
		CXXFLAGS += -mvectorize-with-neon-quad
	endif
	ifeq ($(shell echo `$(CC) -dumpversion` "< 4.9" | bc -l), 1)
		CFLAGS += -march=armv7-a
		CXXFLAGS += -march=armv7-a
	else
		CFLAGS += -march=armv7ve
		CXXFLAGS += -march=armv7ve
		# If gcc is 5.0 or later
		ifeq ($(shell echo `$(CC) -dumpversion` ">= 5" | bc -l), 1)
			CXXFLAGS += -static-libgcc -static-libstdc++
		endif
	endif
	ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
	PLATFORM_EXT := unix
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0
	CORE_DEFINES += -DLOW_END
	
#########################################

# sun8i Allwinner H2+ / H3 for Legacy Builds
# like Orange PI, Nano PI, Banana PI, Tritium, Sunvell R69, AlphaCore2
# by MPCORE-HUB/Liontek1985

else ifeq ($(platform), sun8i_legacy)
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	HAVE_LTCG = 0
	HAVE_OPENMP = 0
	CFLAGS += -Ofast \
	-flto -fuse-linker-plugin \
	-fno-stack-protector -fno-ident -fomit-frame-pointer \
	-fmerge-all-constants -ffast-math -funroll-all-loops \
	-marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
	CXXFLAGS += $(CFLAGS)
	ASFLAGS += $(CFLAGS)
	LDFLAGS += -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -Ofast -flto -fuse-linker-plugin
	ifeq ($(shell echo `$(CC) -dumpversion` "< 4.9" | bc -l), 1)
		CFLAGS += -march=armv7-a
		LDFLAGS += -march=armv7-a
	else
		CFLAGS += -march=armv7ve
		LDFLAGS += -march=armv7ve
		# If gcc is 5.0 or later
		ifeq ($(shell echo `$(CC) -dumpversion` ">= 5" | bc -l), 1)
			LDFLAGS += -static-libgcc -static-libstdc++
		endif
	endif
	PLATFORM_EXT := unix
	WITH_DYNAREC = arm
	HAVE_GENERIC_JIT = 0
	CORE_DEFINES += -DLOW_END
#######################################

# nvidia developer jetson nano kit (jetson-nano)
else ifeq ($(platform), jetson-nano)
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	LDFLAGS +=  -Wl,--no-undefined
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 0
	SINGLE_PREC_FLAGS = 1
	CPUFLAGS += -DTARGET_LINUX_ARMv8 -frename-registers
	CFLAGS += -march=armv8-a+crc -mtune=cortex-a57 -mcpu=cortex-a57+crc+fp+simd $(CPUFLAGS)
	CXXFLAGS += -march=armv8-a+crc -mtune=cortex-a57 -mcpu=cortex-a57+crc+fp+simd $(CPUFLAGS)
	ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
	PLATFORM_EXT := unix
	ARCH=arm
	WITH_DYNAREC=arm64
	HAVE_GENERIC_JIT = 0
	HAVE_VULKAN = 1
	HAVE_LTCG = 0
	LDFLAGS := $(filter-out -flto, $(LDFLAGS))
	CFLAGS := $(filter-out -flto, $(CFLAGS))
	CXXFLAGS := $(filter-out -flto, $(CXXFLAGS))

# Nintendo Switch (Libnx)
else ifeq ($(platform), libnx)
   include $(DEVKITPRO)/libnx/switch_rules
   CC_AS = aarch64-none-elf-as
   TARGET := $(TARGET_NAME)_libretro_$(platform).a
   DEFINES := -DSWITCH=1 -D__SWITCH__=1 -fcommon -DHAVE_LIBNX=1 -DTARGET_LIBNX -DTARGET_NO_OPENMP -DFEAT_NO_RWX_PAGES
   CFLAGS := $(DEFINES) -fPIE -I$(LIBNX)/include/ -I$(PORTLIBS)/include/ -isystem$(CORE_DIR)/core/deps/switch/ -ffunction-sections -fdata-sections -ftls-model=local-exec
   CPUFLAGS += -march=armv8-a -mtune=cortex-a57 -mtp=soft -mcpu=cortex-a57+crc+fp+simd -ffast-math -frename-registers -funroll-loops -ftree-vectorize
   CFLAGS += $(CPUFLAGS) -DTARGET_LIBNX -DTARGET_NO_AREC
   WITH_DYNAREC=arm64
   HAVE_GENERIC_JIT = 0
   STATIC_LINKING = 1
   ENABLE_MODEM = 0
   HAVE_LTCG = 0
   NO_NVMEM = 1
   # stubs
   SOURCES_C += $(CORE_DIR)/core/deps/switch/stubs.c
#######################################

# Odroid-N2
else ifeq ($(platform), odroid-n2)
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	LDFLAGS +=  -Wl,--no-undefined
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 0
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	CPUFLAGS += -DTARGET_LINUX_ARMv8 -frename-registers
	CFLAGS += -mcpu=cortex-a73 -mtune=cortex-a73.cortex-a53 $(CPUFLAGS)
	CXXFLAGS += -mcpu=cortex-a73 -mtune=cortex-a73.cortex-a53 $(CPUFLAGS)
	ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
	PLATFORM_EXT := unix
	WITH_DYNAREC=arm64
	HAVE_GENERIC_JIT = 0
	HAVE_LTCG = 0
	
	# Libre Computer La Frite
else ifeq ($(platform), mali-drm-gles2)
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	LDFLAGS +=  -Wl,--no-undefined
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 0
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	CPUFLAGS += -march=armv8-a
	CFLAGS += -mtune=cortex-a53 $(CPUFLAGS)
	PLATFORM_EXT := unix
	WITH_DYNAREC=arm64
	HAVE_GENERIC_JIT = 0
	HAVE_LTCG = 0

# Amlogic S905/S905X/S912 (AMLGXBB/AMLGXL/AMLGXM) e.g. Khadas VIM1/2 / S905X2 (AMLG12A) & S922X/A311D (AMLG12B) e.g. Khadas VIM3 - 32-bit userspace
else ifneq (,$(findstring AMLG,$(platform)))
  EXT ?= so
  TARGET := $(TARGET_NAME)_libretro.$(EXT)
  SHARED += -shared -Wl,--version-script=link.T
  LDFLAGS +=  -Wl,--no-undefined
  fpic = -fPIC
  LIBS += -lrt
  ARM_FLOAT_ABI_HARD = 1
  FORCE_GLES = 1
  SINGLE_PREC_FLAGS = 1

  CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
  CFLAGS += -march=armv8-a+crc -mfloat-abi=hard -mfpu=neon-fp-armv8 $(CPUFLAGS)
  CXXFLAGS += -march=armv8-a+crc -mfloat-abi=hard -mfpu=neon-fp-armv8 $(CPUFLAGS)

  ifneq (,$(findstring AMLG12,$(platform)))
    ifneq (,$(findstring AMLG12B,$(platform)))
      CFLAGS += -mtune=cortex-a73.cortex-a53
      CXXFLAGS += -mtune=cortex-a73.cortex-a53
    else
      CFLAGS += -mtune=cortex-a53
      CXXFLAGS += -mtune=cortex-a53
    endif
  else ifneq (,$(findstring AMLGX,$(platform)))
    CFLAGS += -mtune=cortex-a53
    CXXFLAGS += -mtune=cortex-a53
    CORE_DEFINES += -DLOW_END
  endif

  ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize

  PLATFORM_EXT := unix
  WITH_DYNAREC=arm
  HAVE_GENERIC_JIT = 0

# Rockchip RK3288 e.g. Asus Tinker Board / RK3328 e.g. PINE64 Rock64 / RK3399 e.g. PINE64 RockPro64 - 32-bit userspace
else ifneq (,$(findstring RK,$(platform)))
  EXT ?= so
  TARGET := $(TARGET_NAME)_libretro.$(EXT)
  SHARED += -shared -Wl,--version-script=link.T
  fpic = -fPIC
  LIBS += -lrt
  ARM_FLOAT_ABI_HARD = 1
  FORCE_GLES = 1
  SINGLE_PREC_FLAGS = 1
  CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
  HAVE_LTCG = 0

  ifneq (,$(findstring RK33,$(platform)))
    CFLAGS += -march=armv8-a+crc -mfpu=neon-fp-armv8
    CXXFLAGS += -march=armv8-a+crc -mfpu=neon-fp-armv8

    ifneq (,$(findstring RK3399,$(platform)))
      CFLAGS += -mtune=cortex-a72.cortex-a53
      CXXFLAGS += -mtune=cortex-a72.cortex-a53
    else ifneq (,$(findstring RK3328,$(platform)))
      CFLAGS += -mtune=cortex-a53
      CXXFLAGS += -mtune=cortex-a53
      CORE_DEFINES += -DLOW_END
    endif

    ifeq ($(HAVE_CLANG),0)
      CFLAGS += -mvectorize-with-neon-quad
      CXXFLAGS += -mvectorize-with-neon-quad
    endif
  else ifneq (,$(findstring RK3288,$(platform)))
    CFLAGS += -march=armv7ve -mtune=cortex-a17 -mfpu=neon-vfpv4
    CXXFLAGS += -march=armv7ve -mtune=cortex-a17 -mfpu=neon-vfpv4
  endif

  CFLAGS += -mfloat-abi=hard $(CPUFLAGS)
  CXXFLAGS += -mfloat-abi=hard $(CPUFLAGS)

  ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
  PLATFORM_EXT := unix
  WITH_DYNAREC=arm
  HAVE_GENERIC_JIT = 0

# RockPro64
else ifeq ($(platform), rockpro64)
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
	CFLAGS += -marm -mfloat-abi=hard -mcpu=cortex-a72 -mtune=cortex-a72.cortex-a53 -mfpu=neon-fp-armv8 $(CPUFLAGS)
	CXXFLAGS += -marm -mfloat-abi=hard -mcpu=cortex-a72 -mtune=cortex-a72.cortex-a53 -mfpu=neon-fp-armv8 $(CPUFLAGS)
	ifeq ($(HAVE_CLANG),0)
		CFLAGS += -mvectorize-with-neon-quad
		CXXFLAGS += -mvectorize-with-neon-quad
	endif
	ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
	PLATFORM_EXT := unix
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0
	HAVE_LTCG = 0

# Tinkerboard
else ifeq ($(platform), tinkerboard)
    EXT ?= so
    TARGET := $(TARGET_NAME)_libretro.$(EXT)
    SHARED += -shared -Wl,--version-script=link.T
    fpic = -fPIC
    LIBS += -lrt
    ARM_FLOAT_ABI_HARD = 1
    FORCE_GLES = 1
    SINGLE_PREC_FLAGS = 1
    CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
    CFLAGS += -marm -mfpu=neon-vfpv4 -mtune=cortex-a17 -mfloat-abi=hard $(CPUFLAGS)
    CXXFLAGS += -marm -mfpu=neon-vfpv4 -mtune=cortex-a17 -mfloat-abi=hard $(CPUFLAGS)
    ASFLAGS += $(CFLAGS) -c -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize
    PLATFORM_EXT := unix
    WITH_DYNAREC=arm
    HAVE_GENERIC_JIT = 0
		
# ODROIDs
else ifneq (,$(findstring odroid,$(platform)))
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	BOARD ?= $(shell cat /proc/cpuinfo | grep -i odroid | awk '{print $$3}')
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	LIBS += -lrt
	ARM_FLOAT_ABI_HARD = 1
	FORCE_GLES = 1
	SINGLE_PREC_FLAGS = 1
	HAVE_LTCG = 0

	CPUFLAGS += -DNO_ASM -DARM_ASM -frename-registers -ftree-vectorize
	CFLAGS += -marm -mfloat-abi=hard $(CPUFLAGS)
	CXXFLAGS += -marm -mfloat-abi=hard $(CPUFLAGS)

	ifneq (,$(findstring ODROIDC,$(BOARD)))
		# ODROID-C1
		MFLAGS += -mcpu=cortex-a5
	else ifneq (,$(findstring ODROID-XU,$(BOARD)))
		# ODROID-XU3, XU4  & XU3 Lite
		ifeq ($(HAVE_CLANG),1)
			MFLAGS += -mcpu=cortex-a15 -mtune=cortex-a15.cortex-a7 -mfpu=neon-vfpv4
		else
			MFLAGS += -mcpu=cortex-a15 -mtune=cortex-a15.cortex-a7 -mfpu=neon-vfpv4 -mvectorize-with-neon-quad
		endif
	else
		# ODROID-U2, -U3, -X & -X2
		MFLAGS += -mcpu=cortex-a9 -mfpu=neon
	endif

	#Since we are using GCC, we use the CFLAGS and we add some extra parameters to be able to compile (taken from reicast/reicast-emulator)
	ASFLAGS += $(CFLAGS) $(MFLAGS) -c  -frename-registers -fno-strict-aliasing -ffast-math -ftree-vectorize

	PLATFORM_EXT := unix
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0

# i.MX6
else ifneq (,$(findstring imx6,$(platform)))
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T
	fpic = -fPIC
	FORCE_GLES = 1
	LIBS += -lrt
	CPUFLAGS += -DNO_ASM
	PLATFORM_EXT := unix
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0

# OS X
else ifneq (,$(findstring osx,$(platform)))
	EXT    ?= dylib
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -dynamiclib
	OSXVER = `sw_vers -productVersion | cut -d. -f 2`
	OSX_LT_MAVERICKS = `(( $(OSXVER) <= 9)) && echo "YES"`
        fpic += -mmacosx-version-min=10.7
	LDFLAGS += -stdlib=libc++
	fpic = -fPIC
	CFLAGS += -DHAVE_GLSYM_PRIVATE
	SINGLE_PREC_FLAGS=1
	PLATCFLAGS += -D__MACOSX__ -DOSX
	GL_LIB := -framework OpenGL
	PLATFORM_EXT := unix
	# Target Dynarec
	ifeq ($(ARCH), $(filter $(ARCH), ppc))
		WITH_DYNAREC =
    else
		HAVE_GENERIC_JIT = 0
	endif
	HAVE_OPENMP=0

# iOS
else ifneq (,$(findstring ios,$(platform)))
	EXT    ?= dylib
	ifeq ($(IOSSDK),)
		IOSSDK := $(shell xcodebuild -version -sdk iphoneos Path)
	endif

	TARGET := $(TARGET_NAME)_libretro_ios.$(EXT)
	DEFINES += -DIOS
	GLES = 1
	WITH_DYNAREC=
	PLATFORM_EXT := unix
	#HOST_CPU_FLAGS = -DHOST_CPU=$(HOST_CPU_ARM)

	PLATCFLAGS += -DHAVE_POSIX_MEMALIGN -DNO_ASM
	PLATCFLAGS += -DIOS -marm
	CPUFLAGS += -DNO_ASM  -DARM -D__arm__ -DARM_ASM -D__NEON_OPT
	CPUFLAGS += -marm -mcpu=cortex-a8 -mfpu=neon -mfloat-abi=softfp
	SHARED += -dynamiclib

	fpic = -fPIC
	GL_LIB := -framework OpenGLES

	CC = clang -arch armv7 -isysroot $(IOSSDK)
	CC_AS = perl ./tools/gas-preprocessor.pl $(CC)
	CXX = clang++ -arch armv7 -isysroot $(IOSSDK)
	ifeq ($(platform),ios9)
		CC         += -miphoneos-version-min=8.0
		CC_AS      += -miphoneos-version-min=8.0
		CXX        += -miphoneos-version-min=8.0
		PLATCFLAGS += -miphoneos-version-min=8.0
	else
		CC += -miphoneos-version-min=5.0
		CC_AS += -miphoneos-version-min=5.0
		CXX += -miphoneos-version-min=5.0
		PLATCFLAGS += -miphoneos-version-min=5.0
	endif
	HAVE_OPENMP=0

# Theos iOS
else ifneq (,$(findstring theos_ios,$(platform)))
	DEPLOYMENT_IOSVERSION = 5.0
	TARGET = iphone:latest:$(DEPLOYMENT_IOSVERSION)
	ARCHS = armv7
	TARGET_IPHONEOS_DEPLOYMENT_VERSION=$(DEPLOYMENT_IOSVERSION)
	THEOS_BUILD_DIR := objs
	include $(THEOS)/makefiles/common.mk

	LIBRARY_NAME = $(TARGET_NAME)_libretro_ios
	DEFINES += -DIOS
	FORCE_GLES = 1
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0

	PLATCFLAGS += -DHAVE_POSIX_MEMALIGN -DNO_ASM
	PLATCFLAGS += -DIOS -marm
	CPUFLAGS += -DNO_ASM  -DARM -D__arm__ -DARM_ASM -D__NEON_OPT -DNOSSE

# Android
else ifneq (,$(findstring android,$(platform)))
	fpic = -fPIC
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro_android.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T -Wl,--no-undefined -Wl,--warn-common

	CC = arm-linux-androideabi-gcc
	CXX = arm-linux-androideabi-g++
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0
	FORCE_GLES = 1
	PLATCFLAGS += -DANDROID
	CPUCFLAGS  += -DNO_ASM
	CPUFLAGS += -marm -mcpu=cortex-a8 -mfpu=neon -mfloat-abi=softfp -D__arm__ -DARM_ASM -D__NEON_OPT
	CFLAGS += -DANDROID

	PLATFORM_EXT := unix
	HAVE_VULKAN = 1

# QNX
else ifeq ($(platform), qnx)
	fpic = -fPIC
	EXT ?= so
	TARGET := $(TARGET_NAME)_libretro_$(platform).$(EXT)
	SHARED += -shared -Wl,--version-script=link.T -Wl,--no-undefined -Wl,--warn-common

	CC = qcc -Vgcc_ntoarmv7le
	CC_AS = qcc -Vgcc_ntoarmv7le
	CXX = QCC -Vgcc_ntoarmv7le
	AR = QCC -Vgcc_ntoarmv7le
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0
	FORCE_GLES = 1
	DEFINES += -DTHREADED_RENDERING_DEFAULT
	PLATCFLAGS += -DNO_ASM -D__BLACKBERRY_QNX__
	CPUFLAGS += -marm -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=softfp -D__arm__ -DARM_ASM -D__NEON_OPT
	CFLAGS += -D__QNX__

	PLATFORM_EXT := unix

# ARM
else ifneq (,$(findstring armv,$(platform)))
	EXT    ?= so
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	SHARED += -shared -Wl,--version-script=link.T -Wl,--no-undefined
	fpic := -fPIC
	CPUFLAGS += -DNO_ASM -DARM -D__arm__ -DARM_ASM -DNOSSE
	WITH_DYNAREC=arm
	HAVE_GENERIC_JIT = 0
	PLATCFLAGS += -DARM
	ifneq (,$(findstring gles,$(platform)))
		FORCE_GLES = 1
	endif
	ifneq (,$(findstring cortexa5,$(platform)))
		CPUFLAGS += -marm -mcpu=cortex-a5
	else ifneq (,$(findstring cortexa8,$(platform)))
		CPUFLAGS += -marm -mcpu=cortex-a8
	else ifneq (,$(findstring cortexa9,$(platform)))
		CPUFLAGS += -marm -mcpu=cortex-a9
	else ifneq (,$(findstring cortexa15a7,$(platform)))
		CPUFLAGS += -marm -mcpu=cortex-a15.cortex-a7
	else
		CPUFLAGS += -marm
	endif
	ifneq (,$(findstring neon,$(platform)))
		CPUFLAGS += -D__NEON_OPT -mfpu=neon
	endif
	ifneq (,$(findstring softfloat,$(platform)))
		CPUFLAGS += -mfloat-abi=softfp
	else ifneq (,$(findstring hardfloat,$(platform)))
		CPUFLAGS += -mfloat-abi=hard
	endif
	DEFINES += -DTHREADED_RENDERING_DEFAULT

# emscripten
else ifeq ($(platform), emscripten)
	EXT       ?= bc
	TARGET := $(TARGET_NAME)_libretro_$(platform).$(EXT)
	FORCE_GLES := 1
	WITH_DYNAREC=
	CPUFLAGS += -Dasm=asmerror -D__asm__=asmerror -DNO_ASM -DNOSSE
	SINGLE_THREAD := 1
	PLATCFLAGS += -Drglgen_resolve_symbols_custom=reicast_rglgen_resolve_symbols_custom \
					  -Drglgen_resolve_symbols=reicast_rglgen_resolve_symbols

	NO_REC=0
	PLATFORM_EXT := unix
	#HAVE_SHARED_CONTEXT := 1

# Windows
else
	ifneq ($(HAVE_GL2), 1)
		ifneq ($(HAVE_OIT), 1)
			HAVE_GL3 = 1
		endif
	endif
	EXT       ?= dll
	HAVE_GENERIC_JIT = 0
	HAVE_CDROM = 1
	TARGET := $(TARGET_NAME)_libretro.$(EXT)
	LDFLAGS += -shared -static-libgcc -static-libstdc++ -Wl,--version-script=link.T -lwinmm -lgdi32
	GL_LIB := -lopengl32
	LIBS := -lws2_32 -liphlpapi
	PLATFORM_EXT := win32
	SINGLE_PREC_FLAGS=1
	CC ?= gcc
	CXX ?= g++
ifeq ($(WITH_DYNAREC), x86)
	LDFLAGS += -m32
	CFLAGS += -m32
endif
	HAVE_VULKAN = 1

endif

ifeq ($(STATIC_LINKING),1)
	fpic=
	SHARED=
endif

ifeq ($(SINGLE_PREC_FLAGS),1)
	CORE_DEFINES += -fno-builtin-sqrtf
endif

ifeq ($(ARMV7A_FLAGS),1)
	MFLAGS += -marm -march=armv7-a
	ASFLAGS += -march=armv7-a
endif

ifeq ($(ARMV7_CORTEX_A9_FLAGS),1)
	MFLAGS += -mcpu=cortex-a9
endif

ifeq ($(ARM_FLOAT_ABI_HARD),1)
	MFLAGS += -mfloat-abi=hard
	ASFLAGS += -mfloat-abi=hard
	CFLAGS += -DARM_HARDFP
endif

ifeq ($(WITH_DYNAREC), $(filter $(WITH_DYNAREC), x86_64 x64))
	HOST_CPU_FLAGS = -DHOST_CPU=$(HOST_CPU_X64)
	HAVE_LTCG = 0
endif

ifeq ($(WITH_DYNAREC), x86)
	HOST_CPU_FLAGS = -DHOST_CPU=$(HOST_CPU_X86)
endif

ifeq ($(WITH_DYNAREC), arm)
	HOST_CPU_FLAGS = -DHOST_CPU=$(HOST_CPU_ARM)
endif

ifeq ($(WITH_DYNAREC), $(filter $(WITH_DYNAREC), arm64 aarch64))
	HOST_CPU_FLAGS = -DHOST_CPU=$(HOST_CPU_ARM64)
endif

ifeq ($(WITH_DYNAREC), mips)
	HOST_CPU_FLAGS = -DHOST_CPU=$(HOST_CPU_MIPS)
endif

ifeq ($(FORCE_GLES),1)
	GLES = 1
	GL_LIB := -lGLESv2
else ifneq (,$(findstring gles,$(platform)))
	GLES = 1
	GL_LIB := -lGLESv2
else ifeq ($(platform), win)
	GL_LIB := -lopengl32
else ifneq (,$(findstring osx,$(platform)))
	GL_LIB := -framework OpenGL
else ifneq (,$(findstring ios,$(platform)))
	GL_LIB := -framework OpenGLES
else ifeq ($(GL_LIB),)
	GL_LIB := -lGL
endif

CFLAGS       += $(HOST_CPU_FLAGS)
CXXFLAGS     += $(HOST_CPU_FLAGS)
RZDCY_CFLAGS += $(HOST_CPU_FLAGS)

include Makefile.common

ifeq ($(WITH_DYNAREC), x86)
	HAVE_LTCG = 0
endif

ifeq ($(DEBUG_ASAN),1)
	DEBUG           = 1
	DEBUG_UBSAN     = 0
	LDFLAGS        += -lasan -fsanitize=address
	CFLAGS         += -fsanitize=address
endif

ifeq ($(DEBUG_UBSAN),1)
	DEBUG           = 1
	CFLAGS         += -fsanitize=undefined
	LDFLAGS        += -lubsan -fsanitize=undefined
endif

ifeq ($(DEBUG),1)
	OPTFLAGS       := -O0
	LDFLAGS        += -g
	CFLAGS         += -g
else
	ifneq (,$(findstring msvc,$(platform)))
		OPTFLAGS       := -O2
	else ifneq (,$(findstring classic_arm,$(platform)))
		OPTFLAGS       := -O2
	else ifeq (,$(findstring classic_arm,$(platform)))
		OPTFLAGS       := -O3
	endif

	CORE_DEFINES   += -DNDEBUG
	LDFLAGS        += -DNDEBUG

	ifeq ($(HAVE_LTCG), 1)
		CORE_DEFINES   += -flto
	endif
endif

ifeq ($(HAVE_GL3), 1)
	HAVE_CORE = 1
	CORE_DEFINES += -DHAVE_GL3
endif

RZDCY_CFLAGS	+= $(CFLAGS) -c $(OPTFLAGS) -frename-registers -ftree-vectorize -fomit-frame-pointer 

ifeq ($(WITH_DYNAREC), arm)
	ifneq (,$(findstring odroid,$(platform)))
		BOARD ?= $(shell cat /proc/cpuinfo | grep -i odroid | awk '{print $$3}')
		ifneq (,$(findstring ODROIDC,$(BOARD)))
			# ODROID-C1
			RZDCY_CFLAGS += -marm -mcpu=cortex-a5
		else ifneq (,$(findstring ODROID-XU,$(BOARD)))
			# ODROID-XU3, XU4 & XU3 Lite
			RZDCY_CFLAGS += -marm -mcpu=cortex-a15 -mtune=cortex-a15.cortex-a7 -mfpu=neon-vfpv4
		else
			# ODROID-U2, -U3, -X & -X2
			RZDCY_CFLAGS += -marm -mcpu=cortex-a9 -mfpu=neon
		endif
	else
		RZDCY_CFLAGS += -march=armv7-a -mcpu=cortex-a9 -mfpu=vfpv3-d16
	endif
	RZDCY_CFLAGS += -DTARGET_LINUX_ARMELv7
else
	RZDCY_CFLAGS += -DTARGET_LINUX_x86
endif

ifeq ($(NO_THREADS),1)
	CORE_DEFINES += -DTARGET_NO_THREADS
else
	NEED_PTHREAD=1
endif

ifeq ($(NO_REC),1)
	CORE_DEFINES += -DTARGET_NO_REC
endif

ifeq ($(NO_REND),1)
	CORE_DEFINES += -DNO_REND=1
endif

ifeq ($(NO_EXCEPTIONS),1)
	CORE_DEFINES += -DTARGET_NO_EXCEPTIONS=1
endif

ifeq ($(NO_NVMEM),1)
	CORE_DEFINES += -DTARGET_NO_NVMEM=1
endif

RZDCY_CXXFLAGS := $(RZDCY_CFLAGS) -fexceptions -fno-rtti -std=gnu++11

ifeq (,$(findstring msvc,$(platform)))
	CORE_DEFINES   += -funroll-loops
endif

ifeq ($(HAVE_OIT), 1)
	HAVE_CORE = 1
	CORE_DEFINES += -DHAVE_OIT -DHAVE_GL4
endif

ifeq ($(HAVE_CORE), 1)
	CORE_DEFINES += -DCORE
endif

ifeq ($(HAVE_TEXUPSCALE), 1)
	CORE_DEFINES += -DHAVE_TEXUPSCALE
ifeq ($(HAVE_OPENMP), 1)
	CFLAGS += -fopenmp
	CXXFLAGS += -fopenmp
	LDFLAGS += -fopenmp
else
	CFLAGS += -DTARGET_NO_OPENMP
	CXXFLAGS += -DTARGET_NO_OPENMP
endif
ifeq ($(platform), win)
	LDFLAGS_END += -Wl,-Bstatic -lgomp -lwsock32 -lws2_32 -liphlpapi
endif
	NEED_CXX11=1
	NEED_PTHREAD=1
endif

ifeq ($(NEED_PTHREAD), 1)
	LIBS         += -lpthread
endif

ifeq ($(HAVE_GL), 1)
	ifeq ($(GLES),1)
		CORE_DEFINES += -DHAVE_OPENGLES -DHAVE_OPENGLES2
	else
		CORE_DEFINES += -DHAVE_OPENGL
	endif
endif

ifeq ($(HAVE_VULKAN), 1)
	CORE_DEFINES += -DHAVE_VULKAN
endif

ifeq ($(DEBUG), 1)
	HAVE_GENERIC_JIT = 0
endif

ifeq ($(HAVE_GENERIC_JIT), 1)
	CORE_DEFINES += -DTARGET_NO_JIT
	NEED_CXX11=1
endif

ifeq ($(NEED_CXX11), 1)
	CXXFLAGS     += -std=c++11
endif

ifeq ($(HAVE_CHD),1)
CORE_DEFINES += -DHAVE_STDINT_H -DHAVE_STDLIB_H -DHAVE_SYS_PARAM_H -D_7ZIP_ST -DUSE_FLAC -DUSE_LZMA
endif

RZDCY_CFLAGS   += $(CORE_DEFINES)
RZDCY_CXXFLAGS += $(CORE_DEFINES)
CFLAGS         += $(CORE_DEFINES)
CXXFLAGS       += $(CORE_DEFINES)

CFLAGS   += $(OPTFLAGS) -c
CFLAGS   += -fno-strict-aliasing
CXXFLAGS += -fno-rtti -fpermissive -fno-operator-names
LIBS     += -lm 

PREFIX        ?= /usr/local

ifneq (,$(findstring arm, $(ARCH)))
	CC_AS    = ${CC_PREFIX}${CC} #The ngen_arm.S must be compiled with gcc, not as
	ASFLAGS  += $(CFLAGS)
endif

ifeq ($(PGO_MAKE),1)
	CFLAGS += -fprofile-generate -pg
	LDFLAGS += -fprofile-generate
else
	CFLAGS += -fomit-frame-pointer
endif

ifeq ($(PGO_USE),1)
	CFLAGS += -fprofile-use
endif

ifeq ($(LTO_TEST),1)
	CFLAGS += -flto -fwhole-program 
	LDFLAGS +=-flto -fwhole-program 
endif

CFLAGS     += $(fpic)
CXXFLAGS   += $(fpic)
LDFLAGS    += $(fpic)

OBJECTS := $(SOURCES_CXX:.cpp=.o) $(SOURCES_C:.c=.o) $(SOURCES_ASM:.S=.o)
OBJECTS:=$(OBJECTS:.cc=.o)

ifneq (,$(findstring msvc,$(platform)))
	OBJOUT = -Fo
	LINKOUT = -out:
	LD = link.exe
else
	LD = $(CXX)
endif

all: $(TARGET)	
$(TARGET): $(OBJECTS)
ifeq ($(STATIC_LINKING), 1)
	$(AR) rcs $@ $(OBJECTS)
else
	$(LD) $(MFLAGS) $(fpic) $(SHARED) $(LDFLAGS) $(OBJECTS) $(LDFLAGS_END) $(GL_LIB) $(LIBS) -o $@
endif

%.o: %.cpp
	$(CXX) $(INCFLAGS) $(CFLAGS) $(MFLAGS) $(CXXFLAGS) $< -o $@
	
%.o: %.c
	$(CC) $(INCFLAGS) $(CFLAGS) $(MFLAGS) $< -o $@

%.o: %.S
	$(CC_AS) $(ASFLAGS) $(INCFLAGS) $< -o $@

%.o: %.cc
	$(CXX) $(INCFLAGS) $(CFLAGS) $(MFLAGS) $(CXXFLAGS) $< -o $@

clean:
	rm -f $(OBJECTS) $(TARGET)

