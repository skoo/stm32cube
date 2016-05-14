BASEDIR := $(dir $(lastword $(MAKEFILE_LIST)))

ifeq ($(CUBE_PROJECT_NAME),)
  $(error CUBE_PROJECT_NAME must be set)
endif

ifeq ($(CUBE_SERIES),)
  $(error CUBE_SERIES must be set)
endif

ifeq ($(CUBE_DEVICE),)
  $(error CUBE_DEVICE must be set)
endif

ifeq ($(CUBE_LINKER_SCRIPT),)
  $(error CUBE_LINKER_SCRIPT must be set)
endif

ifeq ($(CUBE_OPTIMIZATION_LEVEL),)
  $(info CUBE_OPTIMIZATION_LEVEL not set, defaulting to 's')
  CUBE_OPTIMIZATION_LEVEL=s
endif

CUBE_SERIES_UPPER=$(shell echo $(CUBE_SERIES) | tr '[:lower:]' '[:upper:]')
CUBE_DEVICE_LOWER=$(shell echo $(CUBE_DEVICE) | tr '[:upper:]' '[:lower:]')

HAL_DRIVER_BASE=$(BASEDIR)/STM32$(CUBE_SERIES_UPPER)xx_HAL_Driver
CMSIS_BASE= $(BASEDIR)/CMSIS
CMSIS_DEVICE_BASE=$(CMSIS_BASE)/Device/ST/STM32$(CUBE_SERIES_UPPER)xx
LDSCRIPT_INC=$(CMSIS_DEVICE_BASE)/Source/Templates/gcc/linker

CUBE_LIB=stm32$(CUBE_SERIES)_$(CUBE_OPTIMIZATION_LEVEL)

USBD_BASE=$(BASEDIR)/Middlewares/ST/STM32_USB_Device_Library
USBD_CORE_SRC_DIR=$(BASEDIR)/Middlewares/ST/STM32_USB_Device_Library/Core/Src

OPENOCD_PROC_FILE=$(BASEDIR)/openocd/stm32-openocd.cfg
OPENOCD_DEVICE_FILE=$(BASEDIR)/openocd/stm32-device-openocd.cfg

ifeq ($(CROSS_COMPILE),)
	$(error CROSS_COMPILE environment variable must be set)
endif

ifeq ($(OPENOCD_INTERFACE),)
	OPENOCD_INTERFACE=stlink-v2
endif

ifeq ($(OPENOCD_TRANSPORT),)
	OPENOCD_TRANSPORT=hla_swd
endif

CXX = $(CROSS_COMPILE)g++
CC = $(CROSS_COMPILE)gcc
AS = $(CROSS_COMPILE)as
AR = $(CROSS_COMPILE)ar
NM = $(CROSS_COMPILE)nm
LD = $(CROSS_COMPILE)ld
OBJDUMP = $(CROSS_COMPILE)objdump
OBJCOPY = $(CROSS_COMPILE)objcopy
RANLIB = $(CROSS_COMPILE)ranlib
STRIP = $(CROSS_COMPILE)strip
SIZE = $(CROSS_COMPILE)size
GDB = $(CROSS_COMPILE)gdb

CFLAGS  = -Wall -g -std=c99
CFLAGS += -O$(CUBE_OPTIMIZATION_LEVEL)
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -Wl,--gc-sections -Wl,-Map=$(CUBE_PROJECT_NAME).map -Wa,-adhlns=$(CUBE_PROJECT_NAME).lst
CFLAGS += -D$(CUBE_DEVICE)

ifneq ($(CUBE_HSE),)
	CFLAGS += -DHSE_VALUE=$(CUBE_HSE)
endif

ifeq ($(CUBE_SERIES),f0)
	CFLAGS += -mcpu=cortex-m0 -march=armv6-m
endif

ifeq ($(CUBE_SERIES),f1)
	CFLAGS += -mcpu=cortex-m3 -march=armv7-m
endif

ifeq ($(CUBE_SERIES),f4)
	CFLAGS += -mcpu=cortex-m4 -march=armv7e-m -mfloat-abi=hard -mfpu=fpv4-sp-d16
endif

###################################################

CFLAGS += -mthumb -mlittle-endian

CFLAGS += -I inc -I $(HAL_DRIVER_BASE)/Inc/
CFLAGS += -I $(CMSIS_BASE)/Include -I $(CMSIS_DEVICE_BASE)/Include

CUBE_USBD_SRCS_AUDIO = usbd_audio.c
CUBE_USBD_SRCS_HID = usbd_hid.c
CUBE_USBD_SRCS_CDC = usbd_cdc.c
CUBE_USBD_SRCS_MSC = usbd_msc_bot.c usbd_msc.c usbd_msc_scsi.c usbd_msc_data.c usbd_dfu.c
CUBE_USBD_SRCS_CustomHID = usbd_customhid.c

ifneq ($(CUBE_USBD),)
	CFLAGS += -I $(USBD_BASE)/Core/Inc
	CFLAGS += -I $(USBD_BASE)/Class/$(CUBE_USBD)/Inc
	USBD_CLASS_SRC_DIR = $(USBD_BASE)/Class/$(CUBE_USBD)/Src
	CUBE_USBD_SOURCES := usbd_core.c usbd_ctlreq.c usbd_ioreq.c $(CUBE_USBD_SRCS_$(CUBE_USBD))
endif

CFLAGS += $(CUBE_EXTRA_CFLAGS)

vpath %.c src $(USBD_CORE_SRC_DIR) $(USBD_CLASS_SRC_DIR)

OBJS = $(SRCS:.c=.o)

CUBE_STARTUP_SOURCES  = $(CMSIS_DEVICE_BASE)/Source/Templates/gcc/startup_$(CUBE_DEVICE_LOWER).s
CUBE_STARTUP_SOURCES += $(CMSIS_DEVICE_BASE)/Source/Templates/system_stm32$(CUBE_SERIES)xx.c

CUBE_HAL_CONF = -include stm32$(CUBE_SERIES)xx_hal_conf.h

%.o : %.c
	$(CC) $(CFLAGS) -c -o $@ $^

LIB_SRCS := $(wildcard $(HAL_DRIVER_BASE)/Src/*.c)
LIB_OBJS := $(patsubst $(HAL_DRIVER_BASE)/Src/%.c,obj/%.o,$(LIB_SRCS))

obj/%.o :
	$(CC) $(CFLAGS) -ffreestanding -nostdlib -c -o $@ $(patsubst obj/%.o,$(HAL_DRIVER_BASE)/Src/%.c,$@) $^

all: lib$(CUBE_LIB).a proj $(CUBE_PROJECT_NAME).lst

lib$(CUBE_LIB).a: $(LIB_OBJS)
	$(AR) -r $@ $(LIB_OBJS)

proj: 	$(CUBE_PROJECT_NAME).hex $(CUBE_PROJECT_NAME).bin

$(CUBE_PROJECT_NAME).elf: $(CUBE_STARTUP_SOURCES) $(CUBE_USBD_SOURCES) $(CUBE_PROJECT_SOURCES)
	$(CC) $(CFLAGS) -T$(CUBE_LINKER_SCRIPT) -L ./ -L$(LDSCRIPT_INC) $(CUBE_HAL_CONF) \
	  -L src $^ -l $(CUBE_LIB) -o $@
	$(SIZE) $(CUBE_PROJECT_NAME).elf

$(CUBE_PROJECT_NAME).lst: $(CUBE_PROJECT_NAME).elf
	$(OBJDUMP) -St $(CUBE_PROJECT_NAME).elf >$(CUBE_PROJECT_NAME).lst

$(CUBE_PROJECT_NAME).hex: $(CUBE_PROJECT_NAME).elf
	$(OBJCOPY) -O ihex $(CUBE_PROJECT_NAME).elf $(CUBE_PROJECT_NAME).hex
	
$(CUBE_PROJECT_NAME).bin: $(CUBE_PROJECT_NAME).elf
	$(OBJCOPY) -O binary $(CUBE_PROJECT_NAME).elf $(CUBE_PROJECT_NAME).bin
	
program: $(CUBE_PROJECT_NAME).bin
	openocd -c "set STM_TARGET stm32$(CUBE_SERIES)x" \
	-c "set STM_INTERFACE $(OPENOCD_INTERFACE)" \
	-c "set STM_TRANSPORT $(OPENOCD_TRANSPORT)" \
	-f $(OPENOCD_DEVICE_FILE) \
	-f $(OPENOCD_PROC_FILE) -c "stm_flash $(CUBE_SERIES) `pwd`/$(CUBE_PROJECT_NAME).bin" -c shutdown

debug: $(CUBE_PROJECT_NAME).bin
	openocd -c "set STM_TARGET stm32$(CUBE_SERIES)x" \
	-c "set STM_FAMILY $(CUBE_SERIES)" \
	-c "set STM_INTERFACE $(OPENOCD_INTERFACE)" \
	-c "set STM_TRANSPORT $(OPENOCD_TRANSPORT)" \
	-f $(OPENOCD_DEVICE_FILE) \
	-c "init; arm semihosting enable"
	-c "reset halt; resume"

gdb:	$(CUBE_PROJECT_NAME).elf
	$(GDB) -ex "target extended-remote 127.0.0.1:3333" \
	-ex "monitor reset halt" \
	-ex "continue" \
	$(CUBE_PROJECT_NAME).elf

clean:
	find ./ -name '*~' | xargs rm -f
	rm -f *.o
	rm -f $(CUBE_PROJECT_NAME).elf
	rm -f $(CUBE_PROJECT_NAME).hex
	rm -f $(CUBE_PROJECT_NAME).bin
	rm -f $(CUBE_PROJECT_NAME).map
	rm -f $(CUBE_PROJECT_NAME).lst

clean-lib:
	rm -f $(OBJS) lib$(CUBE_LIB).a
	rm -f obj/*.o

reallyclean: clean clean-lib
