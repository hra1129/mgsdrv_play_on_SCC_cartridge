mgsdrv_h_timi_rel	:= 0xC000						; 0x400 bytes : H.TIMI処理ルーチン置き場
my_slot_no			:= 0xC400						; 1byte : この ROM が存在するスロット番号 e00YYyy
													;         yy = page1 primary slot, YY = page1 secondary slot, e = expanded
page1_slot			:= my_slot_no + 1				; 1byte
page2_slot			:= page1_slot + 1				; 1byte
