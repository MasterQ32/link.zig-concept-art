const std = @import("std");

const Linker = @import("Linker.zig");

comptime {
    _ = link;
}

// Link the file into such an executable:
// https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/firmware-image-format.html

pub fn link(linker: *Linker) !void {
    linker.format = .binary;

    // Declaring memory ranges, so the linker can validate if we actually put code into executable places
    const mem_hp_ram = linker.addMemory(.{
        .base = 0x4080_0000,
        .length = 0x0008_0000, // 512K
        .flags = .{ .read = true, .write = true, .execute = true },
    });
    const mem_lp_ram = linker.addMemory(.{
        .base = 0x5000_0000,
        .length = 0x0000_4000, //  16K
        .flags = .{ .read = true, .write = true, .execute = false },
    });
    const mem_rom = linker.addMemory(.{
        .base = 0x2000_0000,
        .length = 0x1000_0000, // 256M
        .flags = .{ .read = true, .write = false, .execute = false },
    });
    const mem_xip = linker.addMemory(.{
        .base = 0x4200_0000,
        .length = 0x0100_0000, //  16M
        .flags = .{ .read = true, .write = false, .execute = true },
    });
    const mem_periph = linker.addMemory(.{
        .base = 0x6000_0000,
        .length = 0x000D_0000, // 832K
        .flags = .{ .read = true, .write = true, .execute = false },
    });

    // we don't use them tho
    _ = mem_hp_ram;
    _ = mem_lp_ram;
    _ = mem_rom;
    _ = mem_xip;
    _ = mem_periph;

    const hdrseg = linker.addProgramHeader("hdrseg", .{ .load = true }); //         hdrseg    PT_LOAD;
    const codeseg = linker.addProgramHeader("codeseg", .{ .load = true }); //       codeseg   PT_LOAD;
    const rodataseg = linker.addProgramHeader("rodataseg", .{ .load = true }); //   rodataseg PT_LOAD;
    const dataseg = linker.addProgramHeader("dataseg", .{ .load = true }); //       dataseg   PT_LOAD;

    const section_alignment = 16;

    // Forward declaration
    const data_begin = linker.declareSymbol("__start_data");
    const data_end = linker.declareSymbol("__stop_data");
    const text_begin = linker.declareSymbol("__start_text");
    const text_end = linker.declareSymbol("__stop_text");
    const rodata_begin = linker.declareSymbol("__start_rodata");
    const rodata_end = linker.declareSymbol("__stop_rodata");
    const entry_point = linker.declareSymbol("_start");

    const start_xip = 0x42000000;
    const start_sram = 0x40800000;

    _ = linker.defineGlobalSymbol("__start_xip", .abs, start_xip, .{}); //                      __start_xip  = 0x42000000;
    _ = linker.defineGlobalSymbol("__start_sram", .abs, start_sram, .{}); //                    __start_sram = 0x40800000;

    // Sections:

    const esp_hdr_sect = linker.createSection(".esphdr", .{ .header = hdrseg, .fill = 0xFFFFFFFF }); //             .esphdr : AT(0) { ... } :hdrseg

    const data_hdr_sect = linker.createSection(".espseg.1", .{ .header = dataseg, .fill = 0xFFFFFFFF }); //         .espseg.0 : AT(LOADADDR(.esphdr) + SIZEOF(.esphdr)) { ... } :hdrseg
    const data_sect = linker.createSection(".data", .{ .header = dataseg, .fill = 0xFFFFFFFF }); //                 .data : AT(SIZEOF(.esphdr) + SIZEOF(.espseg.0)) { ... } :dataseg

    const text_hdr_sect = linker.createSection(".espseg.0", .{ .header = codeseg, .fill = 0xFFFFFFFF }); //         .espseg.1 : AT(LOADADDR(.data) + SIZEOF(.data)) { ... } :codeseg
    const text_sect = linker.createSection(".text", .{ .header = codeseg, .fill = 0xFFFFFFFF }); //                 .text : AT(LOADADDR(.espseg.1) + SIZEOF(.espseg.1)) { ... } :codeseg

    const rodata_hdr_sect = linker.createSection(".espseg.2", .{ .header = rodataseg, .fill = 0xFFFFFFFF }); //     .espseg.2 : AT(LOADADDR(.text) + SIZEOF(.text)) { ... } :rodataseg
    const initarray_sect = linker.createSection(".init_array", .{ .header = rodataseg, .fill = 0xFFFFFFFF }); //    .init_array : AT(LOADADDR(.espseg.2) + SIZEOF(.espseg.2)) { ... } :rodataseg
    const rodata_sect = linker.createSection(".rodata", .{ .header = rodataseg, .fill = 0xFFFFFFFF }); //           .rodata : AT(LOADADDR(.init_array) + SIZEOF(.init_array)) { ... } :rodataseg

    const bss_sect = linker.createSection(".bss", .{ .header = null });
    const padding_checksum_sect = linker.createSection(".padding", .{ .header = null, .fill = 0x00 });

    // SETUP RAM SYMBOLS
    {
        linker.setVirtualAddress(&.{ .literal = start_sram }); //                                                . = __start_sram;

        // .data:
        {
            data_sect.begin(); // for real linker scripts, we have to sadly use those
            defer data_sect.end();

            _ = data_sect.defineSymbol("__start_data", .rel, 0, .{}); //                        __start_data = .;
            _ = data_sect.defineSymbol("__global_pointer$", .rel, 0, .{}); //                   __global_pointer$ = .;

            data_sect.includeSymbols(".sdata", .{}); //                                         *(.sdata)
            data_sect.includeSymbols(".sdata*", .{}); //                                        *(.sdata*)
            data_sect.includeSymbols(".data", .{}); //                                          *(.data)
            data_sect.includeSymbols(".data*", .{}); //                                         *(.data*)

            linker.alignVirtualAddress(section_alignment);
            _ = data_sect.defineSymbol("__stop_data", .rel, 0, .{}); //                         __stop_data = .;
        }

        // .bss:
        {
            bss_sect.begin(); // for real linker scripts, we have to sadly use those
            defer bss_sect.end();

            _ = bss_sect.defineSymbol("__start_bss", .rel, 0, .{}); //                          __start_bss = .;
            bss_sect.includeSymbols(".sbss", .{}); //                                           *(.sbss)
            bss_sect.includeSymbols(".sbss*", .{}); //                                          *(.sbss*)
            bss_sect.includeSymbols(".bss", .{}); //                                            *(.bss)
            bss_sect.includeSymbols(".bss*", .{}); //                                           *(.bss*)

            linker.alignVirtualAddress(section_alignment); //                                   . = ALIGN(__section_alignment);
            _ = bss_sect.defineSymbol("__stop_bss", .rel, 0, .{}); //                           __stop_bss = .;
        }
    }

    // SETUP FLASH SYMBOLS
    {
        linker.setVirtualAddress(&.{ .literal = start_xip }); //                                                 . = __start_xip;

        // ESP32 firmware image format header:
        {
            esp_hdr_sect.begin();
            defer esp_hdr_sect.end();

            // File Header
            esp_hdr_sect.emitLiteral(u8, 0xE9); //                                              BYTE(0xE9);       /* Magic byte. */
            esp_hdr_sect.emitLiteral(u8, 3); //                                                 BYTE(3);          /* Segment count. */
            esp_hdr_sect.emitLiteral(u8, 0x02); //                                              BYTE(0x02);       /* SPI mode. */
            esp_hdr_sect.emitLiteral(u8, 0x10); //                                              BYTE(0x10);       /* SPI speed/size. */
            esp_hdr_sect.emitReference(entry_point); //                                         LONG(_start);     /* Entrypoint. */

            // Extended File Header
            esp_hdr_sect.emitLiteral(u8, 0xee); //                                              BYTE(0xee);       /* WP pin state. */
            esp_hdr_sect.emitLiteral(u8, 0x00); //                                              BYTE(0x00);       /* Drive settings. */
            esp_hdr_sect.emitLiteral(u8, 0x00); //                                              BYTE(0x00);
            esp_hdr_sect.emitLiteral(u8, 0x00); //                                              BYTE(0x00);
            esp_hdr_sect.emitLiteral(u16, 0x000D); //                                           SHORT(0x000D);    /* Chip (ESP32-C6). */
            esp_hdr_sect.emitLiteral(u8, 0x00); //                                              BYTE(0x00);       /* (deprecated) */
            esp_hdr_sect.emitLiteral(u8, 0x0000); //                                            SHORT(0x0000);    /* Min chip rev. */
            esp_hdr_sect.emitLiteral(u8, 0x0000); //                                            SHORT(0x0000);    /* Max chip rev. */
            esp_hdr_sect.emitLiteral(u32, 0x00000000); //                                       LONG(0x00000000); /* (reserved) */
            esp_hdr_sect.emitLiteral(u8, 0x00); //                                              BYTE(0x00);       /* SHA256 appended (not appended). */

        }

        // header for .data:
        {
            data_hdr_sect.begin();
            defer data_hdr_sect.end();

            const section_length = data_hdr_sect.defineComputedSymbol(null, SymbolDistance{
                .end = data_end,
                .begin = data_begin,
            });

            data_hdr_sect.emitReference(data_begin); //                                         LONG(__start_data);
            data_hdr_sect.emitReference(section_length); //                                     LONG(__stop_data - __start_data);
        }

        // allocate space for .data, will be relocated via pyhsical_address to this place in flash later
        linker.incrementVirtualAddress(data_sect.getSize()); //                                      . = . + SIZEOF(.data);

        // header for .text:
        {
            data_hdr_sect.begin();
            defer data_hdr_sect.end();
            const section_length = text_hdr_sect.defineComputedSymbol(null, SymbolDistance{
                .end = text_end,
                .begin = text_begin,
            });
            text_hdr_sect.emitReference(text_begin); //                                         LONG(__start_text);
            text_hdr_sect.emitReference(section_length); //                                     LONG(__stop_text - __start_text);
        }

        // .text:
        {
            data_hdr_sect.begin();
            defer data_hdr_sect.end();
            _ = text_sect.defineSymbol("__start_text", .rel, 0, .{}); //                        __start_text = .;
            linker.alignVirtualAddress(256); //                                                 . = ALIGN(256);

            text_sect.includeSymbols(".interrupt_vector_table", .{}); //                        *(.interrupt_vector_table)
            text_sect.includeSymbols(".text", .{}); //                                          *(.text)
            text_sect.includeSymbols(".text*", .{}); //                                         *(.text*)

            linker.alignVirtualAddress(section_alignment); //                                   . = ALIGN(__section_alignment);
            _ = text_sect.defineSymbol("__stop_text", .rel, 0, .{}); //                         __stop_text = .;
        }

        // header for .rodata:
        {
            rodata_hdr_sect.begin();
            defer rodata_hdr_sect.end();

            const section_length = rodata_hdr_sect.defineComputedSymbol(null, SymbolDistance{
                .end = rodata_end,
                .begin = rodata_begin,
            });
            rodata_hdr_sect.emitReference(rodata_begin); //                                     LONG(__start_rodata);
            rodata_hdr_sect.emitReference(section_length); //                                   LONG(__stop_rodata - __start_rodata);
        }

        // .init_array + .rodata
        {
            _ = initarray_sect.defineSymbol("__start_rodata", .rel, 0, .{}); //                 __start_rodata = .;
            {
                initarray_sect.begin();
                defer initarray_sect.end();

                _ = initarray_sect.defineSymbol("__start_init_array", .rel, 0, .{}); //         __start_init_array = .;
                initarray_sect.includeSymbols(".init_array", .{ .keep = true }); //             KEEP(*(.init_array))
                _ = initarray_sect.defineSymbol("__stop_init_array", .rel, 0, .{}); //          __stop_init_array = .;
            }
            {
                rodata_sect.begin(); // .rodata : AT(0) {
                defer rodata_sect.end(); // }

                rodata_sect.includeSymbols(".rodata", .{}); //                                  *(.rodata)
                rodata_sect.includeSymbols(".rodata*", .{}); //                                 *(.rodata*)
                rodata_sect.includeSymbols(".srodata", .{}); //                                 *(.srodata)
                rodata_sect.includeSymbols(".srodata*", .{}); //                                *(.srodata*)

                linker.alignVirtualAddress(section_alignment); //                               . = ALIGN(__section_alignment);
            }
            _ = rodata_sect.defineSymbol("__stop_rodata", .rel, 0, .{}); //                     __stop_rodata = .;
        }

        // We are aligned to 16 bytes, so we just emit 16 times 0, the checksum is filled in post processing
        {
            padding_checksum_sect.begin();
            defer padding_checksum_sect.end();

            padding_checksum_sect.emitLiteral(u32, 0x00);
            padding_checksum_sect.emitLiteral(u32, 0x00);
            padding_checksum_sect.emitLiteral(u32, 0x00);
            padding_checksum_sect.emitLiteral(u32, 0x00);
        }
    }

    // Define physical (binary image) layout
    {
        const section_order = [_]*Linker.Section{
            esp_hdr_sect,
            data_hdr_sect,
            text_sect,
            text_hdr_sect,
            data_sect,
            rodata_hdr_sect,
            initarray_sect,
            rodata_sect,
            padding_checksum_sect,
        };

        // we load the sections one after another at address 0
        var addr = linker.compute(&.{ .literal = 0 });

        for (section_order) |sect| {
            sect.setPhysicalAddress(addr);
            addr = linker.compute(&.{ .add = .{ addr, sect.getSize() } });
        }

        // esp_hdr_sect.setPhysicalAddress(addr); //    .esphdr : AT(0) {
        // addr = linker.compute(.{ .add = .{ addr, esp_hdr_sect.getSize() } });
        // data_hdr_sect.setPhysicalAddress(addr); //   .espseg.0 : AT(LOADADDR(.esphdr) + SIZEOF(.esphdr)) {
        // addr = linker.compute(.{ .add = .{ addr, data_hdr_sect.getSize() } });
        // text_sect.setPhysicalAddress(addr); //       .data : AT(SIZEOF(.esphdr) + SIZEOF(.espseg.0)) {
        // addr = linker.compute(.{ .add = .{ addr, text_sect.getSize() } });
        // text_hdr_sect.setPhysicalAddress(addr); //   .espseg.1 : AT(LOADADDR(.data) + SIZEOF(.data)) {
        // addr = linker.compute(.{ .add = .{ addr, text_hdr_sect.getSize() } });
        // data_sect.setPhysicalAddress(addr); //       .text : AT(LOADADDR(.espseg.1) + SIZEOF(.espseg.1)) {
        // addr = linker.compute(.{ .add = .{ addr, data_sect.getSize() } });
        // rodata_hdr_sect.setPhysicalAddress(addr); // .espseg.2 : AT(LOADADDR(.text) + SIZEOF(.text)) {
        // addr = linker.compute(.{ .add = .{ addr, rodata_hdr_sect.getSize() } });
        // initarray_sect.setPhysicalAddress(addr); //  .init_array : AT(LOADADDR(.espseg.2) + SIZEOF(.espseg.2)) {
        // addr = linker.compute(.{ .add = .{ addr, initarray_sect.getSize() } });
        // rodata_sect.setPhysicalAddress(addr); //     .rodata : AT(LOADADDR(.init_array) + SIZEOF(.init_array)) {

        // https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/firmware-image-format.html#footer
        // padding_checksum_sect.setPhysicalAddress(addr);

    }

    // ENTRY(_start)
    linker.setEntryPoint(entry_point);

    // This is optional and will perform the linking.
    const artifact = linker.link();

    // We can now perform post processing on section contents and write the checksum to the right place:
    {
        const Range = struct {
            begin: *Linker.Symbol,
            end: *Linker.Symbol,
        };
        const section_ranges = [_]Range{
            .{ .begin = data_begin, .end = data_end },
            .{ .begin = text_begin, .end = text_end },
            .{ .begin = rodata_begin, .end = rodata_end },
        };

        const checksum: u8 = blk: {
            var checksum: u8 = 0xEF;

            for (section_ranges) |range| {
                const start = artifact.getPhysicalSymbolOffset(range.begin);
                const end = artifact.getPhysicalSymbolOffset(range.end);

                for (start..end) |offset| {
                    checksum ^= artifact.readIntLittle(offset, u8);
                }
            }

            break :blk checksum;
        };

        artifact.writeIntLittle(
            artifact.getPhysicalSectionOffset(padding_checksum_sect) + 15,
            u8,
            checksum,
        );
    }
}

const SymbolDistance = struct {
    end: *Linker.Symbol,
    begin: *Linker.Symbol,

    pub fn compute(sd: *SymbolDistance, linker: *Linker) u64 {
        return linker.getSymbolOffset(sd.end) - linker.getSymbolOffset(sd.begin);
    }
};
