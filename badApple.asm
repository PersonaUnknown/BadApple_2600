;------------------------------------------------
;
; Atari VCS Game 
; by Eric Yelong Tabuchi
;
; dasm "badApple.asm" -I"$bB/includes" -f3 -o"badApple.bin"
;------------------------------------------------
	processor 	6502
	include 	vcs.h
	include 	macro.h

;------------------------------------------------
; Constants
;------------------------------------------------
SCORE_COLOR = #$0E
GRASS = #$CA
SKY = #$9C
TREE_WOOD = #$E4
TREE_LEAVES = #$B2
APPLES = #$34
BASKET = #$E8

; 80 (Grass) + 72 (Sky)
PLAYER_Y = #12
APPLE_Y = #66

SPRITE_HEIGHT = #9
APPLE_HEIGHT = #4
APPLE_FALL_DELAY = #15
MOVE_LEFT = #%11100000
MOVE_RIGHT = #%00100000

GAME_MODE_INACTIVE = #0
GAME_MODE_PLAYING = #1

SCORE_DIGIT_HEIGHT = #7

SONG_HEIGHT = #244

; Game Mode Differences
; 0 = Normal (No Changes)
; 1 = Decreased falling delay of apples
; 2 = Decreased width of basket and apples
; 3 = Triple Apples + Baskets
; 4 = Small baskets and apples + decreased falling delay
; 5 = Triple player sprites and decreased falling delay
NORMAL_NUSIZ = #%00110101 ; Wider basket / apples
SMALL_NUSIZ = #%00110000   ; Regular apples / basket
TRIPLE_NUSIZ = #%00110110 ; Triple missiles and player sprites
;------------------------------------------------
; RAM
;------------------------------------------------
    SEG.U   variables
    ORG     $80
	
; Random Seed
randomSeed	.byte

; Score
score			.byte
onesScore		.byte
tensScore		.byte
onesScoreGfx	ds 2
tensScoreGfx	ds 2

; Frame Counter
frame		.byte
idleTimer	.byte
selectTimer	.byte

; Game Mode
gameMode	.byte
gmNumber    .byte

; Apple Drop Delay
dropDelay	.byte

; Player 0 (Basket)
p0y			.byte
p0gfx		.byte
sprite0gfx	ds 2

; Player 1 (Apple)
p1y			.byte
p1gfx		.byte
sprite1gfx	ds 2

; Sprite Index Addressing Mode Holders
basketY		.byte
appleY		.byte

; Dummy for wasting time
dummy		.byte

; Sounds
collectSfx	.byte
gameOverSfx .byte

; Colors
scoreColor	.byte
grassColor	.byte
skyColor	.byte
woodColor	.byte
leafColor	.byte
appleColor	.byte
basketColor	.byte

; Flags
ssFlag		.byte	; Screensaver Flag

; Music
musicControl	ds 2
musicFreq		ds 2
musicRests		ds 2
musicLength		.byte
musicPointer .byte
musicTimer   .byte

; Game Altering Values
playerNusiz	 .byte
appleNusiz	 .byte
fallDelayMax .byte
fallDelay	 .byte
fallSpeed    .byte
fallTimer	 .byte

	echo [($100 - *)]d, " RAM bytes used"

;------------------------------------------------
; Start of ROM
;------------------------------------------------
	SEG   Bank0
	ORG   $F000       	; 4k ROM start point
		
Start 
	CLEAN_START			; Clear RAM and Registers
	lda		#$FF
	sta		AUDV0
	sta		AUDV1

;------------------------------------------------
; INITIALIZE GAME
;------------------------------------------------

; Player Stuff
	lda		#PLAYER_Y	
	sta		p0y		
	
	lda		#APPLE_Y
	sta		p1y
	
	lda		#SPRITE_HEIGHT
	sta		basketY
	sta		appleY
	
	lda		#0
	sta		onesScore
	sta		tensScore
		
.initRAM

	; Sprite Graphics Pointers
	lda		#<BasketSprite	; Bottom byte
	sta		sprite0gfx
	lda		#>BasketSprite	; Upper byte
	sta		sprite0gfx+1
	
	lda		#<AppleSprite
	sta		sprite1gfx
	lda		#>AppleSprite
	sta		sprite1gfx+1
	
	; Initialize score
	lda		#<DigitsOnes
	sta		onesScoreGfx
	lda		#>DigitsOnes
	sta		onesScoreGfx+1
	
	lda		#<DigitsTens
	sta		tensScoreGfx
	lda		#>DigitsTens
	sta		tensScoreGfx+1

	; Double sprite width (basket)
	lda		#%00000101
	sta		NUSIZ0
	
	; Initialize Colors
	lda		#SCORE_COLOR
	sta		scoreColor
	lda		#SKY
	sta		skyColor
	lda		#TREE_WOOD
	sta		woodColor
	lda		#TREE_LEAVES
	sta		leafColor
	lda		#APPLES
	sta		appleColor
	lda		#BASKET
	sta		basketColor
	lda		#GRASS
	sta		grassColor

	; Init first measure		
	ldy		#SONG_HEIGHT
	lda		(musicControl),y
	sta		AUDC0
	lda		(musicFreq),y
	sta		AUDF0
	lda		#10
	sta		musicTimer
	
	lda		#SONG_HEIGHT
	sta		musicLength
	dec 	musicLength
	
	lda		#<MusicControlData
	sta		musicControl
	lda		#>MusicControlData
	sta		musicControl+1
	
	lda		#<MusicFreqData
	sta		musicFreq
	lda		#>MusicFreqData
	sta		musicFreq+1
	
	lda		#<MusicRestData
	sta		musicRests
	lda		#>MusicRestData
	sta		musicRests+1

;------------------------------------------------
; Vertical Blank
;------------------------------------------------
MainLoop
	;***** Vertical Sync routine
	lda		#2
	sta  	VSYNC 	; begin vertical sync, hold for 3 lines
	sta  	WSYNC 	; 1st line of vsync
	sta  	WSYNC 	; 2nd line of vsync
	sta  	WSYNC 	; 3rd line of vsync
	lda  	#43   	; set up timer for end of vblank
	sta  	TIM64T
	lda 	#0
	sta  	VSYNC 	; turn off vertical sync - also start of vertical blank

	;***** Vertical Blank code goes here
	lda		#$00
	sta		PF0
	sta		PF1
	sta		PF2

	; Check to mute
	lda		ssFlag
	cmp		#1
	beq		CheckMusicSS
	lda		gameOverSfx
	cmp		#0
	beq		.muteGameOver
	dec		gameOverSfx
	jmp		CheckMusicSS
.muteGameOver
	; Mute sounds
	lda		#0
	sta		AUDV0
	sta		AUDC0
	sta		AUDF0

; Music Implementation (For screensaver)
CheckMusicSS
	lda		ssFlag
	cmp		#1
	beq		.continueMusicSS
	jmp		.endCheckMusicSS
.continueMusicSS
	; Check musicTimer
	lda		musicTimer
	cmp		#0
	beq		.nextMeasure
	
	; Timer still going so keep playing song
	lda		#5
	sta		AUDV0
	ldy		musicLength
	lda		(musicControl),y
	sta		AUDC0
	lda		(musicFreq),y
	sta		AUDF0
	
	dec musicTimer
	jmp		.endMusic
.nextMeasure
	; Check if you reached end of song
	lda		musicLength
	cmp		#0
	beq		.resetSong

	; Next measure
	dec		musicLength
	ldy		musicLength
	
	; Reset musicTimer
	lda		(musicRests),y
	sta		musicTimer
	jmp		.endMusic
.resetSong
	lda		#SONG_HEIGHT
	sta		musicLength
	ldy		musicLength
	lda		(musicRests),y
	sta		musicTimer
.endMusic
.endCheckMusicSS
; Screensaver Implementation
	lda		frame
	and		#90
	cmp		#90
	bne		.endScreenSaver
	lda		ssFlag
	cmp		#1
	bne		.endScreenSaver
.screenSaver
	; Change colors of everything
	inc 	leafColor
	inc		scoreColor
	inc		appleColor
	inc		skyColor
	inc		woodColor
	inc		basketColor
	inc		grassColor
.endScreenSaver
	lda		leafColor
	sta		COLUBK

; ==================
; Check Game Mode
; ==================
CheckGameMode
	; Check which game mode it is (inactive or active)
	lda		gameMode
	cmp		GAME_MODE_INACTIVE
	bne		.activeGameMode
	jmp		.inactiveGameMode
.activeGameMode
	jmp		EndCheckGameMode
.inactiveGameMode
; ==================
; Set Up Random Seed
; ==================
	inc		frame
	lda		frame
	cmp		#120
	bne		.endCheckRandomSeed
	lda		#0
	sta		frame
	inc		idleTimer
.endCheckRandomSeed
	
	; Currently inactive, so we must wait for joystick0 fire button to be pressed
CheckJoy0Fire
	lda		#%10000000
	bit		INPT4
	bne		.noGameStart
	jmp		.reset
.noGameStart
	jmp		.endCheckJoy0Fire
.reset
	; Reset everything = Now you are playing

	lda		#GAME_MODE_PLAYING
	sta		gameMode
	nop
	nop
	sta		RESP0	
	lda		frame
	sta		randomSeed
	lda		#0
	sta		frame
	sta		onesScore
	sta		tensScore
	sta		ssFlag
	sta		idleTimer
	sta		selectTimer
	sta		AUDV0
	sta		AUDC0
	sta		AUDF0
	
	; Reset Colors
	lda		#SCORE_COLOR
	sta		scoreColor
	lda		#SKY
	sta		skyColor
	lda		#TREE_WOOD
	sta		woodColor
	lda		#TREE_LEAVES
	sta		leafColor
	lda		#APPLES
	sta		appleColor
	lda		#BASKET
	sta		basketColor
	lda		#GRASS
	sta		grassColor

	lda		#0
	sta		fallTimer
	lda		#5
	sta		fallSpeed

	; Check Game Mode
	lda		gmNumber
	cmp		#0
	bne		.endCheckGM0
	lda		#NORMAL_NUSIZ
	sta		playerNusiz
	sta		appleNusiz
	
	lda		#10
	sta		fallDelayMax 
	lda		fallDelayMax
	sta		dropDelay
	jmp		.endCheckGM4
.endCheckGM0
	cmp		#1
	bne		.endCheckGM1
	lda		#NORMAL_NUSIZ
	sta		playerNusiz
	sta		appleNusiz
	
	lda		#0
	sta		fallDelayMax 
	lda		fallDelayMax
	sta		dropDelay
	jmp		.endCheckGM4
.endCheckGM1
	cmp		#2
	bne		.endCheckGM2

	lda		#SMALL_NUSIZ
	sta		playerNusiz
	sta		appleNusiz

	lda		#15
	sta		fallDelayMax 
	lda		fallDelayMax
	sta		dropDelay
	jmp		.endCheckGM4
.endCheckGM2
	cmp		#3
	bne		.endCheckGM3

	lda		#TRIPLE_NUSIZ
	sta		playerNusiz
	sta		appleNusiz
	
	lda		#15
	sta		fallDelayMax 
	lda		fallDelayMax
	sta		dropDelay
	jmp		.endCheckGM4
.endCheckGM3
	cmp		#4
	bne		.endCheckGM4

	lda		#SMALL_NUSIZ
	sta		playerNusiz
	sta		appleNusiz

	lda		#0
	sta		fallDelayMax 
	lda		fallDelayMax
	sta		dropDelay
.endCheckGM4
	cmp		#5
	bne		.endCheckGM5

	lda		#TRIPLE_NUSIZ
	sta		playerNusiz
	sta		appleNusiz

	lda		#0
	sta		fallDelayMax 
	lda		fallDelayMax
	sta		dropDelay
.endCheckGM5
	
	; Waste time for random seed
	ldx		randomSeed
.wasteInitRandomTime
	rol		dummy
	dex
	bne		.wasteInitRandomTime
	sta		RESP1
.endCheckJoy0Fire
	; Anything else to check for idle screen
CheckSelect
	lda		#%00000010
	bit		SWCHB
	bne		.resetDebounce	
	
	; Debounce select switch
	lda		selectTimer
	cmp		#0
	bne		.endCheckSelect
	
	lda		#1
	sta		selectTimer
	
	; Check if onesScore is <= 4
	lda		gmNumber
	cmp		#5
	beq		.resetGameMode
	inc		gmNumber
	jmp		.endCheckSelect
.resetGameMode
	lda		#0
	sta		gmNumber
	jmp		.endCheckSelect
.resetDebounce
	lda		#0
	sta		selectTimer
.endCheckSelect

; ==================
; Check Screensaver
; ==================
CheckScreenSaver
	; Check idleTimer to see if you waited long enough for screensaver to play
	lda		idleTimer
	cmp		#30
	beq		.setScreenFlag
	jmp		.endCheckScreenSaver
.setScreenFlag
	; Set flag to start changing colors
	lda		#1
	sta		ssFlag
.endCheckScreenSaver
	; Load and set the correct pointer for the score for each player
	ldx		gmNumber
	lda		DigitOnesOffsets,x
	sta		onesScoreGfx
	lda		#>DigitsOnes
	sta		onesScoreGfx+1

	jmp		.waitForVBlank
EndCheckGameMode

; ===================
; CHECK SOUND EFFECTS
; ===================
.checkCollectSfx
	; Check to mute
	lda		collectSfx
	cmp		#0
	beq		.muteCollect
	dec		collectSfx
	jmp		InputDetection
.muteCollect
	; Mute sounds
	lda		#0
	sta		AUDV1
	sta		AUDC1
	sta		AUDF1

	lda		p1y
	cmp		#APPLE_Y
	beq		.setRandomSeed
	jmp		InputDetection
.setRandomSeed
	lda		frame
	sta		randomSeed

; ===================
; CHECK PLAYER INPUT
; ===================
InputDetection
	; delay input detection
	inc		frame
	;lda		frame
	;and		#2
	;cmp		#2
	;beq		.continueInput
	;jmp		EndInputDetection

.continueInput

; =======================
; Player0 Joystick Inputs
; =======================
; Check Reset Switch
CheckResetSwitch
	lda		#%00000001		; bit 0 = reset switch
	bit		SWCHB
	bne		.endCheckResetSwitch
	lda		GAME_MODE_INACTIVE
	sta		gameMode
	jsr		ResetGameValues
.endCheckResetSwitch

CheckJoy0Right
	lda		#%01000000
	bit		SWCHA
	bne		.endCheckJoy0Right
	lda		#MOVE_RIGHT
	sta		HMP0
	jmp 	EndInputDetection
.endCheckJoy0Right

CheckJoy0Left
    lda 	#%10000000
    bit 	SWCHA
	bne		EndInputDetection
	lda		#MOVE_LEFT
	sta		HMP0
	jmp 	EndInputDetection

EndInputDetection

	inc		fallTimer

	lda		fallSpeed
	cmp		#0
	beq		.appleStart
	lda		fallTimer
	cmp		fallSpeed
	beq		.appleStart
	jmp 	.endAppleReset
; =======================
; Apple Management
; =======================
.appleStart
	lda		#0
	sta		fallTimer
	lda		p1y
	cmp		#APPLE_HEIGHT+4
	beq		.resetAppleYPos
	
	; Check delay
	lda		dropDelay
	cmp		#0
	beq		.canFall
	
	; Delay is non-zero so decrease
	dec		dropDelay
	jmp		.endAppleReset
.canFall
	dec		p1y
	jmp		.endAppleReset
.resetAppleYPos	
	; Reset y-position
	lda		#APPLE_Y
	sta		p1y
	
	lda		frame
	sta		randomSeed
	
	; Reset drop delay
	lda		fallDelayMax
	sta		dropDelay

	; Check for collisions at this point (apple has fully fallen)
checkCollisionP0P1
	lda		CXPPMM
	and		#$80
	bne		.endCheckCollisionP0P1
	
	; In event of no collision, you lose
	; Play sound effect
	lda		#$03
	sta		AUDV0
	lda		#$06
	sta		AUDC0
	sta		AUDF0
	
	lda		#20
	sta		gameOverSfx

	lda		GAME_MODE_INACTIVE
	sta		gameMode
	jsr		ResetGameValuesGameOver
  
	; Wait for VB
	jmp		.waitForVBlank
.endCheckCollisionP0P1

	; In event of collision between basket and apple, carry on like nothing happened
; ===========================
; Increment a two-digit score
; ===========================
	inc 	score

	; Check to alter fallSpeed
	lda		score
	cmp		#5
	beq		.decSpeed

	cmp		#10
	beq		.decSpeed
	
	cmp		#30
	beq		.decSpeed

	cmp		#50
	beq		.decSpeed

	cmp		#70
	beq		.decSpeed
	jmp		.incScore

.decSpeed
	dec		fallSpeed
	
.incScore
	; Check ones place first
	lda		onesScore
	cmp		#9
	bne		.addFirstDigit

	; Ones places = 9 --> Reset to 0 
	lda		#0
	sta		onesScore
	
	; Check if you need to increment tens place
	lda		tensScore
	cmp		#9
	bne		.addSecondDigit

	; Tens place = 9 --> Reset two digit score to 0
	lda		#0
	sta		tensScore
	sta		score
	lda		#5
	sta		fallSpeed
	jmp		.endScoreCalc

.addFirstDigit
	inc		onesScore
	jmp		.endScoreCalc

.addSecondDigit
	inc		tensScore
.endScoreCalc

	; Play sound effect
	lda		#$03
	sta		AUDV1
	lda		#%00001100
	sta		AUDC1
	sta		AUDF1
	
	lda		#5
	sta		collectSfx
.endAppleReset

	; Load and set the correct pointer for the score for each player
	ldx		onesScore
	lda		DigitOnesOffsets,x
	sta		onesScoreGfx
	lda		#>DigitsOnes
	sta		onesScoreGfx+1

	ldx		tensScore
	lda		DigitTensOffsets,x
	sta		tensScoreGfx
	lda		#>DigitsTens
	sta		tensScoreGfx+1

; =======================
; Wait For VBlank
; =======================

.waitForVBlank
	lda		INTIM
	bne		.waitForVBlank
	sta		WSYNC
	sta		HMOVE
	sta		CXCLR
	sta		VBLANK

; Reset player position
	ldx		#3
.waste
	lda		$FF,x
	nop
	dex	
	bne		.waste
	sta		WSYNC
	
	lda		#0
	sta		HMP0
	sta		HMM0
	sta 	WSYNC

;------------------------------------------------
; Kernel
;------------------------------------------------	

; If game is inactive, draw title
	lda		gameMode
	cmp		#GAME_MODE_INACTIVE
	beq		.idleScreen	
	sta		RESM0
	jmp		DrawScreen

.idleScreen		
	; Title set-up
	lda		appleColor
	sta		COLUP1
	lda		#%00000001
	sta		NUSIZ1

	ldx		#9
.top
	lda		appleColor
	sta		COLUPF
	; Load front half
	lda		#0
	sta		PF0
	lda		TitlePF1-1,x
	sta		PF1
	lda		TitlePF2-1,x
	sta		PF2
	
	; Load back half
	nop
	nop
	nop
	nop
	nop
	lda		#0
	sta		PF1
	sta		PF2

	dex
	sta		WSYNC
	bne		.top
	
	sta		WSYNC
	sta		WSYNC
	sta		WSYNC
	sta		WSYNC
	sta		WSYNC
	
	ldx		#9
.top2
	lda		#0
	sta		PF0
	lda		TitleBotPF1-1,x
	sta		PF1
	lda		TitleBotPF2-1,x
	sta		PF2
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	lda		TitleBotPF0-1,x
	sta		PF0
	lda		#0
	sta		PF1
	sta		PF2
	
	dex
	sta		WSYNC
	bne		.top2
	
	lda		leafColor
	sta		COLUPF

	sta		WSYNC
	
	ldx		#10
.leaves_bottom1
	lda		woodColor
	sta		COLUBK
	lda		LeavesPF0-1,x
	sta		PF0
	lda		LeavesPF1-1,x
	sta		PF1
	lda		LeavesPF2-1,x
	sta		PF2
	
	lda		LeavesPF1-1,x
	sta		PF0
	lda		LeavesPF2-1,x
	sta		PF1
	lda		LeavesPF0-1,x
	sta		PF2
	dex
	sta		WSYNC
	bne		.leaves_bottom1

	lda		woodColor
	sta		COLUPF
	lda		#%11000000
	sta		PF0
	lda		#%11111000
	sta		PF1
	lda		#%00011111
	sta		PF2
	
	lda		skyColor
	sta		COLUBK
	
	; Player score color
	lda		skyColor
	sta		COLUP0
	lda		appleColor
	sta		COLUP1
	
	ldx		#64
.sky1

	; Sprite Graphics (Apple & Basket)
	lda		#0
	sta		GRP0
	sta		WSYNC 
	
	; Apple Sprite
	cpx		p1y
	bne		.loadSpriteApple1
	lda		#APPLE_HEIGHT
	sta		appleY
.loadSpriteApple1
	lda		appleY		
	cmp		#$FF
	beq		.noSpriteApple1
	tay
	lda		(sprite1gfx),y
	sta		p1gfx
	dec		appleY
	jmp		.endSpriteApple1

.noSpriteApple1
	lda		#0
	sta		p1gfx
.endSpriteApple1
	
	; Basket Sprite
	cpx		p0y
	bne		.loadSpriteBasket1
	lda		#SPRITE_HEIGHT
	sta		basketY
.loadSpriteBasket1
	ldy		basketY
	cpy		#$FF
	beq		.noSpriteBasket1
	lda		(sprite0gfx),y
	sta		p0gfx
	dec		basketY
	jmp		.endSpriteBasket1
.noSpriteBasket1
	lda		#0
	sta		p0gfx
.endSpriteBasket1
	dex
	sta		WSYNC
	bne		.sky1

	lda		#0
	sta		PF0
	sta		PF1
	sta		PF2

	; Drawing a two-digit score
	sta		RESP1
	lda		grassColor
	sta		COLUBK
	
	; Waste Time To Center Score
	rol		dummy
	inc		dummy
	lda		dummy
	lda		dummy
	lda		dummy
	ldx		#14
	dex
	
	; Make Sure Player 1 sprite is wide
	lda		#%00000101
	sta		NUSIZ1
	
	; Number of Scan Lines for Score
	ldx 	#14	
	
	; Player score color
	lda		scoreColor
	sta		COLUP1
.score1
	lda		p1gfx
	sta		GRP1

	; Score sprites
	cpx		#14
	bne		.loadScore1
	ldy		#SCORE_DIGIT_HEIGHT
.loadScore1
	cpy		#$FF
	beq		.noScoreSprite1
	lda		(onesScoreGfx),y
	sta		p1gfx
	dey
	jmp		.endScore1
.noScoreSprite1
	lda		#0
	sta		p1gfx
.endScore1

	dex
	sta		WSYNC
	sta		WSYNC
	bne		.score1

	; Reset size of player 1 sprites (for apples)
	lda		#%00000000
	sta		NUSIZ1
	
	jmp		.overscan


; Else the game is playing
DrawScreen
	lda		#%00110110
	sta		NUSIZ0
	sta		NUSIZ1	

	lda		appleColor
	sta		COLUP0
	sta		COLUP1
	nop
	sta		RESM0
	nop
	sta		RESM1
	lda		#%11111111
	sta		ENAM0
	sta		ENAM1
	
	ldx		#9
.leaves
	dex
	sta		WSYNC
	bne		.leaves


	lda		#0
	sta		ENAM0
	sta		ENAM1
	sta		WSYNC

	nop
	nop
	rol		dummy
	rol		dummy
	rol		dummy
	rol		dummy
	rol		dummy
	nop
	sta		RESM1
	nop
	sta		RESM0
	sta		WSYNC

	sta		WSYNC
	sta		WSYNC
	sta		WSYNC

	lda		#%11111111
	sta		ENAM0
	sta		ENAM1

	ldx		#9
.leaves2
	dex
	sta		WSYNC
	bne		.leaves2

	lda		leafColor
	sta		COLUPF
	
	lda		#%00000101
	sta		NUSIZ0
	lda		#0
	sta		NUSIZ1
	sta		ENAM0
	sta		ENAM1
	sta		WSYNC
	
	ldx		#10
.leaves_bottom
	lda		woodColor
	sta		COLUBK
	lda		LeavesPF0-1,x
	sta		PF0
	lda		LeavesPF1-1,x
	sta		PF1
	lda		LeavesPF2-1,x
	sta		PF2
	
	lda		LeavesPF1-1,x
	sta		PF0
	lda		LeavesPF2-1,x
	sta		PF1
	lda		LeavesPF0-1,x
	sta		PF2
	dex
	sta		WSYNC
	bne		.leaves_bottom

	lda		woodColor
	sta		COLUPF
	lda		#%11000000
	sta		PF0
	lda		#%11111000
	sta		PF1
	lda		#%00011111
	sta		PF2
	
	lda		skyColor
	sta		COLUBK
	
	; Player score color
	lda		basketColor
	sta		COLUP0
	lda		appleColor
	sta		COLUP1
	
	lda		playerNusiz
	sta		NUSIZ0
	lda		appleNusiz
	sta		NUSIZ1
	
	ldx		#64
.sky

	; Sprite Graphics (Apple & Basket)
	lda		p0gfx
	sta		GRP0
	lda		p1gfx
	sta		GRP1
	sta		WSYNC 
	
	; Apple Sprite
	cpx		p1y
	bne		.loadSpriteApple
	lda		#APPLE_HEIGHT
	sta		appleY
.loadSpriteApple
	lda		appleY		
	cmp		#$FF
	beq		.noSpriteApple
	tay
	lda		(sprite1gfx),y
	sta		p1gfx
	dec		appleY
	jmp		.endSpriteApple

.noSpriteApple
	lda		#0
	sta		p1gfx
.endSpriteApple
	
	; Basket Sprite
	cpx		p0y
	bne		.loadSpriteBasket
	lda		#SPRITE_HEIGHT
	sta		basketY
.loadSpriteBasket
	ldy		basketY
	cpy		#$FF
	beq		.noSpriteBasket
	lda		(sprite0gfx),y
	sta		p0gfx
	dec		basketY
	jmp		.endSpriteBasket
.noSpriteBasket
	lda		#0
	sta		p0gfx
.endSpriteBasket
	dex
	sta		WSYNC
	bne		.sky

	lda		#0
	sta		PF0
	sta		PF1
	sta		PF2

	; Drawing a two-digit score
	lda		grassColor
	sta		COLUBK
	
	; Waste Time To Center Score
	rol		dummy
	inc		dummy
	lda		dummy
	lda		dummy
	lda		dummy
	ldx		#14
	dex
	sta		RESP1
	
	; Make Sure Player 1 sprite is wide
	lda		#%00000101
	sta		NUSIZ1
	
	; Number of Scan Lines for Score
	ldx 	#14	
	
	; Player score color
	lda		scoreColor
	sta		COLUP1
.score
	lda		p1gfx
	sta		GRP1
	
	; Score sprites
	cpx		#14
	bne		.loadScore
	ldy		#SCORE_DIGIT_HEIGHT
.loadScore
	cpy		#$FF
	beq		.noScoreSprite
	lda		(tensScoreGfx),y
	ora		(onesScoreGfx),y
	sta		p1gfx
	dey
	jmp		.endScore
.noScoreSprite
	lda		#0
	sta		p1gfx
.endScore

	dex
	sta		WSYNC
	sta		WSYNC
	bne		.score

	; Reset size of player 1 sprites (for apples)
	lda		#%00000000
	sta		NUSIZ1

.overscan
;------------------------------------------------
; Overscan
;------------------------------------------------
	lda		#%01000010
	sta		WSYNC
	sta		VBLANK
    lda		#36
    sta		TIM64T

	;***** Overscan Code goes here	
	lda		#0
	sta		ENAM0
	sta		ENAM1

	lda 	randomSeed
	and		#20
	tax
.wasteRandomTime
	dex
	bne		.wasteRandomTime
	
	; Update horizontal positioning
	sta		RESP1
	
.waitForOverscan
	lda     INTIM
	bne     .waitForOverscan

	jmp		MainLoop

;------------------------------------------------
; Subroutines
;------------------------------------------------
ResetGameValuesGameOver
	; Reset Major Values
	lda		frame
	sta		randomSeed

	lda		#5
	sta		fallSpeed
	
	lda		#0
	sta		AUDF1
	sta		AUDV1
	sta		AUDC1
	sta		ENAM0
	sta		ENAM1
	sta		NUSIZ0
	sta		HMM0
	sta		HMM1
	sta		RESP0
	sta		HMBL
	sta		idleTimer
	sta		ssFlag
	sta		selectTimer
	sta		frame
	sta		gameMode
	sta		onesScore
	sta		tensScore
	sta		score
	sta		fallTimer
	rts

ResetGameValues
	; Reset Major Values
	lda		frame
	sta		randomSeed

	lda		#5
	sta		fallSpeed

	lda		#0
	sta		AUDF1
	sta		AUDV1
	sta		AUDC1
	sta		ENAM0
	sta		ENAM1
	sta		HMM0
	sta		NUSIZ0
	sta		HMM1
	sta		HMBL
	sta		idleTimer
	sta		ssFlag
	sta		selectTimer
	sta		frame
	sta		RESP0
	sta		gameMode
	sta		onesScore
	sta		tensScore
	sta		score
	sta		fallTimer
	
	; Reset Apple Height Back to Top
	lda		#APPLE_Y
	sta		p1y		
	rts

;------------------------------------------------
; ROM Tables
;------------------------------------------------
;***** ROM tables go here
	align 256
DigitsTens
zeroRight
	.byte	%00000010
	.byte	%00000101
	.byte	%00000101
	.byte	%00000101
	.byte	%00000101
	.byte	%00000101
	.byte	%00000101
	.byte	%00000010
oneRight
	.byte	%00000111
	.byte	%00000010
	.byte	%00000010
	.byte	%00000010
	.byte	%00000010
	.byte	%00000010
	.byte	%00000110
	.byte	%00000010
twoRight
	.byte	%00000111
	.byte	%00000100
	.byte	%00000010
	.byte	%00000001
	.byte	%00000001
	.byte	%00000101
	.byte	%00000101
	.byte	%00000010
threeRight
	.byte	%00000010
	.byte	%00000101
	.byte	%00000001
	.byte	%00000001
	.byte	%00000010
	.byte	%00000001
	.byte	%00000101
	.byte	%00000010
fourRight
	.byte	%00000001
	.byte	%00000001
	.byte	%00000001
	.byte	%00000111
	.byte	%00000101
	.byte	%00000101
	.byte	%00000011
	.byte	%00000001
fiveRight
	.byte	%00000010
	.byte	%00000101
	.byte	%00000001
	.byte	%00000001
	.byte	%00000010
	.byte	%00000100
	.byte	%00000100
	.byte	%00000111
sixRight
	.byte	%00000010
	.byte	%00000101
	.byte	%00000101
	.byte	%00000101
	.byte	%00000111
	.byte	%00000100
	.byte	%00000100
	.byte	%00000011
sevenRight
	.byte	%00000010
	.byte	%00000010
	.byte	%00000010
	.byte	%00000010
	.byte	%00000001
	.byte	%00000001
	.byte	%00000001
	.byte	%00000111
eightRight
	.byte	%00000010
	.byte	%00000101
	.byte	%00000101
	.byte	%00000101
	.byte	%00000010
	.byte	%00000101
	.byte	%00000101
	.byte	%00000010
nineRight
	.byte	%00000010
	.byte	%00000101
	.byte	%00000001
	.byte	%00000001
	.byte	%00000111
	.byte	%00000101
	.byte	%00000101
	.byte	%00000111
	
DigitsOnes
zeroLeft
	.byte	%00100000
	.byte	%01010000
	.byte	%01010000
	.byte	%01010000
	.byte	%01010000
	.byte	%01010000
	.byte	%01010000
	.byte	%00100000
oneLeft
	.byte	%01110000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%01100000
	.byte	%00100000
twoLeft
	.byte	%01110000
	.byte	%01000000
	.byte	%00100000
	.byte	%00010000
	.byte	%00010000
	.byte	%01010000
	.byte	%01010000
	.byte	%00100000
threeLeft
	.byte	%00100000
	.byte	%01010000
	.byte	%00010000
	.byte	%00010000
	.byte	%00100000
	.byte	%00010000
	.byte	%01010000
	.byte	%00100000
fourLeft
	.byte	%00010000
	.byte	%00010000
	.byte	%00010000
	.byte	%01110000
	.byte	%01010000
	.byte	%01010000
	.byte	%00110000
	.byte	%00010000
fiveLeft
	.byte	%00100000
	.byte	%01010000
	.byte	%00010000
	.byte	%00010000
	.byte	%01100000
	.byte	%01000000
	.byte	%01000000
	.byte	%01110000
sixLeft
	.byte	%00100000
	.byte	%01010000
	.byte	%01010000
	.byte	%01010000
	.byte	%01110000
	.byte	%01000000
	.byte	%01000000
	.byte	%00110000
sevenLeft
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00100000
	.byte	%00010000
	.byte	%00010000
	.byte	%00010000
	.byte	%01110000
eightLeft
	.byte	%00100000
	.byte	%01010000
	.byte	%01010000
	.byte	%01010000
	.byte	%00100000
	.byte	%01010000
	.byte	%01010000
	.byte	%00100000
nineLeft
	.byte	%00100000
	.byte	%01010000
	.byte	%00010000
	.byte	%00010000
	.byte	%01110000
	.byte	%01010000
	.byte	%01010000
	.byte	%01110000
DigitOnesOffsets
	.byte 	<zeroRight
	.byte 	<oneRight
	.byte 	<twoRight
	.byte 	<threeRight
	.byte 	<fourRight
	.byte 	<fiveRight
	.byte 	<sixRight
	.byte 	<sevenRight
	.byte 	<eightRight
	.byte 	<nineRight
DigitTensOffsets
	.byte 	<zeroLeft
	.byte 	<oneLeft
	.byte 	<twoLeft
	.byte 	<threeLeft
	.byte 	<fourLeft
	.byte 	<fiveLeft
	.byte 	<sixLeft
	.byte 	<sevenLeft
	.byte 	<eightLeft
	.byte 	<nineLeft
LeavesPF0
	.byte	#%00000000
	.byte	#%00011000
	.byte	#%01011000
	.byte	#%01111110
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
LeavesPF1
	.byte	#%00000000
	.byte	#%00000000
	.byte	#%00011000
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
LeavesPF2
	.byte	#%00000000
	.byte	#%00011100
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
BasketSprite
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%11111111
	.byte	#%10000001
	.byte	#%10000001
	.byte	#%01000010
	.byte	#%00111100
AppleSprite
	.byte	#%01111110
	.byte	#%01111110
	.byte	#%01111110
	.byte	#%01111110
	.byte	#%01111110
; Top part of title (B A D)
TitlePF0
	.byte	#%11110000
	.byte	#%10100000
	.byte	#%00100000
	.byte	#%01100000
	.byte	#%00100000
	.byte	#%10100000
	.byte	#%10100000
	.byte	#%11110000
TitlePF1
	.byte	#%11100100
	.byte	#%01010100
	.byte	#%01010100
	.byte	#%01010111	
	.byte	#%01100100
	.byte	#%01010100
	.byte	#%01010100
	.byte	#%11100011
	.byte	#$00
TitlePF2
	.byte	#%00011101
	.byte	#%00101001
	.byte	#%00101001
	.byte	#%00101001
	.byte	#%00101001
	.byte	#%00101001
	.byte	#%00101001
	.byte	#%00011100
	.byte	#$00
; Bottom part of title (A P P L E)
TitleBotPF0
	.byte	#%11110000
	.byte	#%10010000
	.byte	#%10010000
	.byte	#%00010000
	.byte	#%01110000
	.byte	#%00010000
	.byte	#%10010000
	.byte	#%11110000
	.byte	#$00
TitleBotPF1
	.byte	#%10101000
	.byte	#%10101000
	.byte	#%10101000
	.byte	#%11101000
	.byte	#%10101110
	.byte	#%10101010
	.byte	#%10101010
	.byte	#%01001110
	.byte	#$00
TitleBotPF2
	.byte	#%01110001
	.byte	#%00010001
	.byte	#%00010001
	.byte	#%00010001
	.byte	#%00010111
	.byte	#%00010101
	.byte	#%00010101
	.byte	#%00010111
	.byte	#$00

	
; Values for AUDC0
MusicControlData
; M36
	.byte	0
	.byte	0
	.byte	12
	.byte	4
	.byte	4
	.byte	12
	.byte	12

; M35
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	12
	.byte	12
	
; M34
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4

; M33
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	.byte	4
	
; M32
	.byte	4
	.byte	4
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	4

; M31
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M30
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M29
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M28
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M27
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M26
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M25
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M24
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M23
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M22
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M21
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M20
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M19
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M18
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M17
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M16
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M15
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M14
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M13
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M11
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M10
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M9
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	
; M8
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M7
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M6
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M5
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M4
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M3
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M2
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; M1
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12
	.byte	12

; Silence	
	.byte	12
	
; Values for AUDF0
MusicFreqData
; M36
	.byte	0
	.byte	0
	.byte	13
	.byte	28
	.byte	31
	.byte   11
	.byte	12
	
; M35
	.byte	13
	.byte	15
	.byte	13
	.byte	15
	.byte	12
	.byte	11
	.byte	31

; M34
	.byte 	28
	.byte 	31
	.byte 	28
	.byte 	31
	.byte 	28
	.byte 	20
	.byte 	23

; M33
	.byte 	28
	.byte 	31
	.byte 	28
	.byte 	31
	.byte 	28
	.byte 	20
	.byte 	23

; M32
	.byte	23
	.byte	28
	.byte	13
	.byte   15
	.byte	12
	.byte	11
	.byte	31

; M31
	.byte	18
	.byte	20
	.byte	18
	.byte	15
	.byte	13
	.byte	12
	.byte	11

; M30
	.byte	12
	.byte	13
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15

; M29
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15

; M28
	.byte	15
	.byte	18
	.byte	27
	.byte	18
	.byte	20
	.byte	23
	.byte	24

; M27
	.byte	27
	.byte	31
	.byte	27
	.byte	31
	.byte	24
	.byte	23
	.byte	20

; M26
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15
	
; M25
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15

; M24
	.byte	15
	.byte	18
	.byte	27
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	
; M23
	.byte	27
	.byte	31
	.byte	27
	.byte	31
	.byte	24
	.byte	23
	.byte	20

; M22
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15

; M21
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15

; M20
	.byte	15
	.byte	18
	.byte	27
	.byte	18
	.byte	20
	.byte	23
	.byte	24

; M19
	.byte	27
	.byte	31
	.byte	27
	.byte	31
	.byte	24
	.byte	23
	.byte	20

; M18
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15

; M17
	.byte	18
	.byte	20
	.byte	18
	.byte	20
	.byte	18
	.byte	13
	.byte	15
	
; M16
	.byte	18
	.byte	20
	.byte	23
	.byte	24

; M15
	.byte	23
	.byte	20
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; M14
	.byte   24
	.byte	23
	.byte   20
	.byte   18
	.byte   13
	.byte	18

; M13
	.byte	15
	.byte	13
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; M12
	.byte	24
	.byte	29
	.byte	27
	.byte	24
	.byte	23
	.byte	24
	.byte	27
	.byte	24

; M11
	.byte	23
	.byte	20
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; M10
	.byte   24
	.byte	23
	.byte   20
	.byte   18
	.byte   13
	.byte	18

; M9
	.byte	15
	.byte	13
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27	

; M8
	.byte	18
	.byte	20
	.byte	23
	.byte	24

; M7
	.byte	23
	.byte	20
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; M6
	.byte   24
	.byte	23
	.byte   20
	.byte   18
	.byte   13
	.byte	18

; M5
	.byte	15
	.byte	13
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; M4
	.byte	24
	.byte	29
	.byte	27
	.byte	24
	.byte	23
	.byte	24
	.byte	27
	.byte	24

; M3
	.byte	23
	.byte	20
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; M2
	.byte   24
	.byte	23
	.byte   20
	.byte   18
	.byte   13
	.byte	18

; M1
	.byte	15
	.byte	13
	.byte	18
	.byte	20
	.byte	23
	.byte	24
	.byte	27

; Silence
	.byte	0
	

MusicRestData
; M36 (7)
	.byte   10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M35 (7)
	.byte   10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M34 (7)
	.byte   10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M33 (7)
	.byte   10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M32 (7)
	.byte   10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M31 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M30 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M29 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M28 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M27 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M26 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	
; M25 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M24 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M23 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M22 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M21 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M20 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M19 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M18 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M17 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M16 (4)
	.byte	20
	.byte	20
	.byte   20
	.byte   20

; M15 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M14 (6)
	.byte   10
	.byte   10
	.byte   10
	.byte   10
	.byte   20
	.byte   20

; M13 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	
; M12 (8)
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M11 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M10 (6)
	.byte   10
	.byte   10
	.byte   10
	.byte   10
	.byte   20
	.byte   20

; M9 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M8 (4)
	.byte	20
	.byte	20
	.byte   20
	.byte   20

; M7 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M6 (6)
	.byte   10
	.byte   10
	.byte   10
	.byte   10
	.byte   20
	.byte   20

; M5 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	
; M4 (8)
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M3 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; M2 (6)
	.byte   10
	.byte   10
	.byte   10
	.byte   10
	.byte   20
	.byte   20

; M1 (7)
	.byte	10
	.byte	10
	.byte	20
	.byte	10
	.byte	10
	.byte	10
	.byte	10

; Silence (1)
	.byte	0
	
;------------------------------------------------
; Interrupt Vectors
;------------------------------------------------
	echo [*-$F000]d, " ROM bytes used"
	ORG    $FFFA
	.word  Start         ; NMI
	.word  Start         ; RESET
	.word  Start         ; IRQ
    
	END