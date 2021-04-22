; ==============================================================================
;   Test program of MGSDRV on ROM Cartridge with SCC
; ==============================================================================
		scope		main_program
main_program::
		xor			a, a				; Max master volume
		call		mgs_msvst			; set master colume
		call		play_song			; play the sound
loop:
		ld			de, s_hello
str_loop:
		ld			a, [de]
		or			a, a
		jp			z, exit_loop
		call		chput
		inc			de
		jp			str_loop

exit_loop:
		ld			hl, 50000
wait_loop:
		dec			hl
		nop
		nop
		nop
		ld			a, l
		or			a, h
		jp			nz, wait_loop
		jp			loop

s_hello:
		ds			"Hello, SCC Cartridge!! "
		db			0
		endscope

		include		"MGSDRVCTL.ASM"
