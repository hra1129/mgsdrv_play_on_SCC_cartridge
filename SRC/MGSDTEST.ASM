; ==============================================================================
;   Test program of MGSDRV on ROM Cartridge with SCC
; ==============================================================================
		include		"MSXBIOS.ASM"
		include		"MGSDRV_API.ASM"
		include		"ROM_BANK.ASM"
		include		"WORK.ASM"

BOOT_BANK			:= 0

		org			0x4000
; ==============================================================================
;	ROM Header
; ==============================================================================
rom_header_id:
		ds			"AB"
rom_header_init:
		dw			entry
rom_header_statement:
		dw			0
rom_header_device:
		dw			0
rom_header_text:
		dw			0
rom_header_reserved:
		space		0x0010 - 0x000A, 0

; ==============================================================================
;	Initializer
; ==============================================================================
		scope		entry_point
entry::
		di
		; Initialize Stack Pointer
		ld			hl, [himem]
		ld			de, ramad0
		or			a, a
		sbc			hl, de
		ld			sp, ramad0
		jp			nc, skip1
		ld			sp, [himem]
skip1:
		; Initialize others
		call		init_memory_mapper
		call		get_rom_slot
		call		search_page1_dram_slot
		call		search_page2_dram_slot
		jp			transfer_to_ram
		endscope

; ==============================================================================
;	Initialize Memory Mapper
;
; In MSX1, the BIOS does not include a mapper initialization process, 
; and in some cases, the memory mapper RAM does not initialize the segment 
; registers and all pages have the same segments.
; On the other hand, MSX2 includes a process to initialize segment registers 
; in the BIOS, and allocates 0, 1, 2, and 3 in the order of page3, 2, 1, and 0.
; By initializing the segment registers to 0, 1, 2, 3 in the order of 
; page3, 2, 1, 0, we can avoid the situation where, for example, 
; the same segment appears on page1 and 2, and writing on one will rewrite the other.
; ==============================================================================
		scope		init_memory_mapper
init_memory_mapper::
		xor			a, a
		out			[0xFF], a
		inc			a
		out			[0xFE], a
		inc			a
		out			[0xFD], a
		inc			a
		out			[0xFC], a

		ld			a, [0x002D]
		cp			a, 3					; MSXturboR or later?
		ret			c						; Return when this system is MSX1/2/2+.

		ld			a, 0x81					; R800 ROM Mode
		call		chgcpu
		ret
		endscope

; ==============================================================================
;	Find the slot number where this ROM cartridge exists.
; ==============================================================================
		scope		get_rom_slot
get_rom_slot::
		di
		; Basic slot switching: switch page3 to the same slot as page1
		in			a, [0xA8]
		ld			d, a						; Basic slot register 0xA8 is backed up to D.
		ld			c, a
		and			a, 0b00_11_11_11
		ld			b, a						; B = 00zzyyxx : xx=page0slot, yy=page1slot, zz=page2slot
		ld			a, c
		and			a, 0b00_00_11_00			; A = 0000yy00 : yy=page1slot
		rrca
		rrca
		ld			c, a						; C = 000000yy : yy=page1slot
		rrca
		rrca
		or			a, b						; A = yyzzyyxx : xx=page0slot, yy=page1slot, zz=page2slot

		ld			b, 0
		ld			hl, exptbl
		add			hl, bc
		ld			b, [hl]						; B = Availability of expansion slots

		; Switch the basic slot
		out			[0xA8], a					; Specify the same basic slot number for page3 as for page1

		; Check if an expansion slot exists.
		ld			a, b
		and			a, 0x80
		jr			z, page1_is_not_expanded

		; Expansion Slot Reading
		ld			a, [0xFFFF]
		cpl
		and			a, 0b00_00_11_00			; Expansion slot number for page1
		or			a, 0x80						; Expansion Slot Flag
		or			a, c
		ld			c, a						; C = e000YYyy : yy = page1 primary slot, YY = page1 secondary slot, e = expanded
page1_is_not_expanded:

		; Restore the basic slots.
		ld			a, d
		out			[0xA8], a

		; Save the detected slot number
		ld			a, c
		ld			[my_slot_no], a

		; Change page2 to the detected slot.
		ld			h, 0x80
		call		enaslt

		; Set ROM Bank to 0,1,0,1 (rom_bank0 is set to 0 when this code is running)
		xor			a, a
		ld			[rom_bank2], a
		inc			a
		ld			[rom_bank1], a
		ld			[rom_bank3], a
		ei
		ret
		endscope

; ==============================================================================
;	Detects the DRAM slot of Page1 and sets it to RAMAD1
;		This code will run on page2.
; ==============================================================================
		org			$ + 0x4000
		scope		search_page1_dram_slot
search_page1_dram_slot::
		di
		ld			a, [exptbl + 0]
		and			a, 0x80
		call		search_page1_sub
		ret			nc

		ld			a, [exptbl + 1]
		and			a, 0x80
		or			a, 0x01
		call		search_page1_sub
		ret			nc

		ld			a, [exptbl + 2]
		and			a, 0x80
		or			a, 0x02
		call		search_page1_sub
		ret			nc

		ld			a, [exptbl + 3]
		and			a, 0x80
		or			a, 0x03
		call		search_page1_sub
		ret			nc

not_enough_memory:
		; SCREEN 1
		ld			a, 1
		call		CHGMOD

		ld			hl, error_message
		ld			de, 0x1800				; Pattern name table
		ld			bc, error_message_end - error_message
		call		LDIRVM
		di
		halt
error_message:
					;01234567890123456789012345678901
		ds			"Not enough memory.              "
		ds			"At least 64KB is required."
error_message_end:

search_page1_sub:
		push		af
		; Switch the slot on page1
		ld			h, 0x40
		call		enaslt
		; Check if page1 is RAM.
		ld			hl, 0x4000
		ld			de, 0x4000
loop:
		ld			a, [hl]
		cpl
		ld			[hl], a
		cp			a, [hl]
		cpl
		ld			[hl], a
		jr			nz, no_match
		inc			hl
		dec			de
		ld			a, d
		or			a, e
		jr			nz, loop
match:
		pop			af
		ld			[ramad1], a
		; Switch the slot on page1
		ld			a, [my_slot_no]
		ld			h, 0x40
		call		enaslt
		ei
		or			a, a						; Cy = 0
		ret

no_match:
		pop			af
		or			a, a
		jp			p, not_found
		add			a, 0b0000_01_00
		bit			4, a
		jp			z, search_page1_sub

not_found:
		scf
		ret										; Cy = 1
		endscope
		org			$ - 0x4000

; ==============================================================================
;	Detects the DRAM slot on page2 and sets it to RAMAD1
;		This code will run on page1.
; ==============================================================================
		scope		search_page2_dram_slot
search_page2_dram_slot::
		di
		ld			a, [exptbl + 0]
		and			a, 0x80
		call		search_page2_sub
		ret			nc

		ld			a, [exptbl + 1]
		and			a, 0x80
		or			a, 0x01
		call		search_page2_sub
		ret			nc

		ld			a, [exptbl + 2]
		and			a, 0x80
		or			a, 0x02
		call		search_page2_sub
		ret			nc

		ld			a, [exptbl + 3]
		and			a, 0x80
		or			a, 0x03
		call		search_page2_sub
		ret			nc

not_enough_memory:
		di
		halt

search_page2_sub:
		push		af
		; Switch the slot on page2
		ld			h, 0x80
		call		enaslt
		; Check if page2 is RAM.
		ld			hl, 0x8000
		ld			de, 0x4000
loop:
		ld			a, [hl]
		cpl
		ld			[hl], a
		cp			a, [hl]
		cpl
		ld			[hl], a
		jr			nz, no_match
		inc			hl
		dec			de
		ld			a, d
		or			a, e
		jr			nz, loop
match:
		pop			af
		ld			[ramad2], a
		; Switch the slot on page2
		ld			a, [my_slot_no]
		ld			h, 0x80
		call		enaslt
		ei
		or			a, a						; Cy = 0
		ret

no_match:
		pop			af
		or			a, a
		jp			p, not_found
		add			a, 0b0000_01_00
		bit			4, a
		jp			z, search_page2_sub

not_found:
		scf
		ret										; Cy = 1
		endscope

; ==============================================================================
; Various block transfers
; ==============================================================================
		scope		transfer_to_ram
transfer_to_ram::
		; Jump to page2
		jp			transfer_to_ram_sub

		org			$ + 0x4000
transfer_to_ram_sub:
		; Switch page1 to RAM
		ld			a, [ramad1]
		ld			h, 0x40
		call		enaslt

		; Transfer MGSDRV to page1 (6000h-7fffh) (* rom_bank3 is already MGSDRV_BANK)
		ld			hl, 0xA000			; rom_bank3
		ld			de, 0x6000
		ld			bc, 0x2000
		ldir

		; Switch rom_bank3 to MAIN_PROGRAM_BANK
		ld			a, MAIN_PROGRAM_BANK
		ld			[rom_bank3], a

		; Transfer MAIN_PROGRAM to page1 (4000h-5fffh)
		ld			hl, main_program_transfer_address	; rom_bank3
		ld			de, 0x4000
		ld			bc, 0x2000
		ldir

		; Transfer H.TIMI routine to page3 (*not hooked yet)
		ld			hl, mgsdrv_h_timi
		ld			de, mgsdrv_h_timi_rel
		ld			bc, mgsdrv_h_timi_size
		ldir

		ld			hl, h_timi
		ld			de, old_h_timi
		ld			bc, 5
		ldir
		jp			go_to_main_program			; page3
		endscope

; ==============================================================================
;	Routines that work with page3
; ==============================================================================

; ==============================================================================
;	go_to_main_program
;		Routine to jump to main_program (RAM on page1) at the top of MAIN_PROGRAM.ASM
; ==============================================================================
		scope		mgsdrv_h_timi
mgsdrv_h_timi::
		org			mgsdrv_h_timi_rel
go_to_main_program::
		di
		; Switch rom_bank2 to SCC registers bank
		ld			a, 0x3F
		ld			[rom_bank2], a
		; copy MGS data
		call		copy_mgs_data
		; Switch page1 to RAM slot
		ld			a, [ramad1]
		ld			h, 0x40
		ld			[page1_slot], a
		call		enaslt					; Disable interrupt
		; Switch page2 to RAM slot
		ld			a, [ramad2]
		ld			h, 0x80
		ld			[page2_slot], a
		call		enaslt					; Disable interrupt
		; Initialize MGSDRV
		call		init_mgsdrv
		ei
		jp			main_program
		endscope

; ==============================================================================
;	copy_mgs_data
;		Routine for transferring MGS file images to RAM on page2
; ==============================================================================
		scope		copy_mgs_data
copy_mgs_data::
		; Switch page1 to the ROM slot
		ld			a, [my_slot_no]
		ld			h, 0x40
		call		enaslt					; Disable interrupt
		; Switch page2 to RAM slot
		ld			a, [ramad2]
		ld			h, 0x80
		call		enaslt					; Disable interrupt
		; Switch bank0 (page1) to the bank where MGS is located.
		ld			a, MGS_BANK
		ld			[rom_bank0], a
		inc			a
		ld			[rom_bank1], a
		; page1 --> page2 block transfer
		ld			hl, 0x4000
		ld			de, 0x8000
		ld			bc, 0x4000
		ldir
		; Switch page1 to the original slot.
		ld			a, [page1_slot]
		ld			h, 0x40
		call		enaslt					; Disable interrupt
		; Switch page2 to its original slot.
		ld			a, [page2_slot]
		ld			h, 0x80
		call		enaslt					; Disable interrupt
		ret
		endscope

; ==============================================================================
;	mgsdrv_h_timi_start
;		H.TIMI routine
; ==============================================================================
		scope		mgsdrv_h_timi_start
mgsdrv_h_timi_start::
		call		mgs_inter
old_h_timi::
		ret
		ret
		ret
		ret
		ret
mgsdrv_h_timi_end::

mgsdrv_h_timi_size	:= mgsdrv_h_timi_end - mgsdrv_h_timi_rel

		if mgsdrv_h_timi_size >= 0x400
			error "MGSDRV_H_TIMI is too big!"
		endif

		org			mgsdrv_h_timi + mgsdrv_h_timi_size - 0x4000
		endscope

end_of_boot_code:
		space		(0x6000 - 13) - $, 0

; ==============================================================================
; Place MGSDRV.COM here
; ==============================================================================
MGSDRV_BANK			:= 1

mgsdrv_address::
		binary_link	"../MGSDRV/MGSDRV.COM"

; ==============================================================================
; Main Program (Less than 8192 bytes)
; ==============================================================================
MAIN_PROGRAM_BANK	:= 2

		org			0xA00F
main_program_transfer_address::
		org			0x4000
main_program_address::
		include		"MAIN_PROGRAM.ASM"
		org			$ + 0x000F
		align		8192

; ==============================================================================
; MGS file image
; ==============================================================================
MGS_BANK			:= 3			; 3 and 4

		binary_link	"../MGS/TEST.MGS"
		align		8192
end_of_program::
