extends KinematicBody2D

const SPEED = 250;

export (int) var run_speed
export (int) var jump_speed
export (int) var dash_multiplier
export (int) var gravity = 0
export (float,0,5) var time_before_active=.3

var velocity = Vector2()
#Jumping is identical to falling except that the player can cancel upwards momentium by letting
#go of the jump button.

#Normal is running or idle, there doesn't need to be a distinction anyways
enum State { INACTIVE, NORMAL, JUMPING, FALLING, HURT, GRABBING_LADDER, ON_LADDER, FLYING_BACKWARDS }
var state_toString = ["Normal","Jumping","Falling","Hurt","Grabbing_Ladder","On_Ladder","Flying_Backwards"]
var state = State.INACTIVE


const MAX_HP = 24 #Originally 32
var HP = 24
var grabbingLadder=false

#Maybe this should be an enum?
var inWater = false # *2 height
var inSand = false  # *.25 height
var inSpace = false # *3 height

var timer:float
var timerWithDeath:float
var is_timer_stopped:bool=false

var currentWeapon = Globals.Weapons.Buster;
# Out of 128 in this game (See Globals.gd for more information)
var weaponMeters:PoolIntArray = []
onready var weaponSwitch =$WeaponSwitch
#What the fuck does e20 mean
#Cooldown between shots
var shoot_time = 1e20
#How long to display the shoot sprite
var shoot_sprite_time = 0
var bullet = preload("res://Player Files/bullet.tscn")
var archiRocket = preload("res://Player Files/8bitPlayer/ArchiRocket_Player.tscn")
#This is only used when on normal or higher difficulty. It keeps track of the bullets on screen by storing the variables.
#When a bullet goes off screen or hits an enemy, the slot is replaced by null and a new one can be inserted.
var bulletManager
#Node that holds all the bullets because in easy mode they can't collide with each other
var bulletHolder:Node2D

var splashAnimation = preload("res://Player Files/8bitPlayer/SplashAnim.tscn")
var deathAnimation = preload("res://Animations/deathAnimation.tscn")

#Camera
var stageRoot
var currentCam

#UI
onready var HPBar = $CanvasLayer/bar

onready var footstep = $FootstepSound
onready var sprite = $Sprite
onready var shotTimer = $ShotTimer

onready var eventCheck = $EventCheck

#Cutscenes
var gf_cutscene = preload("res://Cutscene/CutsceneMain.tscn")

#debug
var freeRoam = false
var noClip = false
var rapidFire:bool = (Globals.playerData.gameDifficulty==Globals.Difficulty.BEGINNER)

#var showDebugDisplay:int = 0 #0 - off, 1 - 
onready var debugDisplay = $CanvasLayer/DebugDisplay
onready var stateInfo = $CanvasLayer/DebugDisplay/StateInfo
onready var stateVelocity = $CanvasLayer/DebugDisplay/StateVelocity
onready var stateTile = $CanvasLayer/DebugDisplay/StateTile
onready var statePos = $CanvasLayer/DebugDisplay/StatePosition
onready var cameraInfo = $CanvasLayer/DebugDisplay/CameraInfo
onready var onscreenPos = $CanvasLayer/DebugDisplay/PositionOnScreen

var tiles;
var LADDER_TILE_ID
var LADDER_TOP_TILE_ID
var SPIKES_TILE_ID
var DEATH_TILE_ID
var lastDebugWarped=-1

func _ready():
	
	stageRoot = get_node("/root/Node2D/")
	tiles = self.get_node("/root/Node2D/TileMap");
	LADDER_TILE_ID = stageRoot.LADDER_TILE_ID
	LADDER_TOP_TILE_ID = stageRoot.LADDER_TOP_TILE_ID
	
	if "SPIKES_TILE_ID" in stageRoot:
		SPIKES_TILE_ID = stageRoot.SPIKES_TILE_ID
	else:
		SPIKES_TILE_ID = -999
	
	if "DEATH_TILE_ID" in stageRoot:
		DEATH_TILE_ID = stageRoot.DEATH_TILE_ID
	else:
		DEATH_TILE_ID = -999
	
	var b = load("res://Player Files/8bitPlayer/bulletManager.gd")
	bulletManager=b.new(stageRoot)
	#TODO: This is actually really stupid considering you can spawn a Node2D on the fly...
	bulletHolder = get_node("/root/Node2D/BulletHolder")
	
	debugDisplay.visible=OS.is_debug_build()
	
	if CheckpointPlayerStats.checkpointSet:
		position=CheckpointPlayerStats.lastCheckpointPos
		if len(CheckpointPlayerStats.lastCameraBounds) == 4: #If there is no last camera this would be 0
			print("Restoring camera params: "+String(CheckpointPlayerStats.lastCameraBounds))
			$Camera2D.adjustCamera(CheckpointPlayerStats.lastCameraBounds,0)
		#HP=CheckpointPlayerStats.lastHealth
		timer=CheckpointPlayerStats.timer
		weaponMeters=CheckpointPlayerStats.lastWeaponMeters
		if Globals.playerData.gameDifficulty < Globals.Difficulty.MEDIUM:
			for i in range(weaponMeters.size()):
				weaponMeters[i] = 144
		sprite.flip_h = CheckpointPlayerStats.shouldFaceLeft
	else:
		weaponMeters.resize(Globals.playerData.availableWeapons.size())
		for i in range(weaponMeters.size()):
			weaponMeters[i] = 144
	timerWithDeath=CheckpointPlayerStats.timerWithDeath
	HPBar.updateHP(HP)
	
	sprite.get_material().set_shader_param("clr1", Globals.weaponColorSwaps[currentWeapon][0])
	sprite.get_material().set_shader_param("clr2", Globals.weaponColorSwaps[currentWeapon][1])
	#self.get_node("Sprite").play("Begin");
	sprite.set_animation("Begin")
	sprite.frame=0
	
	

func setDebugInfoText():
	var t = $CanvasLayer/DebugDisplay/FreeRoam
	var st = ""
	if noClip:
		st+="NoClip"
	if freeRoam:
		st = "Free Roam, "+st
	if rapidFire:
		st = "Rapidfire, "+st
	t.text = st

func switchWeapon():
	weaponSwitch.showIcon(currentWeapon)
	sprite.get_material().set_shader_param("clr1", Globals.weaponColorSwaps[currentWeapon][0])
	sprite.get_material().set_shader_param("clr2", Globals.weaponColorSwaps[currentWeapon][1])
	#print(weaponMeters[currentWeapon]/144.0)
	HPBar.show_weapon(currentWeapon!=0,weaponMeters[currentWeapon]/144.0)
	if currentWeapon!=0:
		HPBar.get_material().set_shader_param("clr1", Globals.weaponColorSwaps[currentWeapon][0])
		HPBar.get_material().set_shader_param("clr2", Globals.weaponColorSwaps[currentWeapon][1])
	
	#print(Globals.weaponColorSwaps[currentWeapon][0])
	#print(Globals.weaponColorSwaps[currentWeapon][1])

func get_menu_buttons_input(delta):
	if Input.is_action_just_pressed('DebugButton1'):
		freeRoam = !freeRoam
		setDebugInfoText()
		CheckpointPlayerStats.usedDebugMode=true
		
	elif Input.is_action_just_pressed("DebugButton2"):
		if noClip:
			set_collision_mask_bit(0,true)
			set_collision_layer_bit(0,true)
			noClip = false
		else:
			set_collision_mask_bit(0,false)
			set_collision_layer_bit(0,false)
			noClip = true;
			freeRoam=true
		setDebugInfoText()
		CheckpointPlayerStats.usedDebugMode=true
		
	elif Input.is_action_just_pressed("DebugButton3"):
		if lastDebugWarped+1 < stageRoot.debug_warp_points.size():
			lastDebugWarped+=1
		else:
			lastDebugWarped=0
		#print(tile_scale)
		print("Warped player to "+String(stageRoot.debug_warp_points[lastDebugWarped]*tile_scale))
		position = stageRoot.debug_warp_points[lastDebugWarped]*64
		$Camera2D.adjustCamera([-10000000,-10000000,10000000,10000000],0)

	
	elif Input.is_action_just_pressed("DebugButton4"):
		print(bulletManager.bullets)
		rapidFire = !rapidFire
		setDebugInfoText()
		CheckpointPlayerStats.usedDebugMode=true
		

		
	elif Input.is_action_just_pressed("DebugButton5"):
		HP = MAX_HP
		HPBar.updateHP(HP)
		for i in range(weaponMeters.size()):
			weaponMeters[i] = 144
		if currentWeapon!=0:
			HPBar.updateAmmo(1.0,false)
		CheckpointPlayerStats.usedDebugMode=true
		pass
		
	elif Input.is_action_just_pressed("DebugButton6"):
		#position = Vector2(0,-100)
		$Camera2D.adjustCamera([-10000000,-10000000,10000000,10000000],0)
	elif Input.is_action_just_pressed("DebugButton7"):
		var c = $Camera2D
		var cPos = c.get_camera_screen_center()
		c.limit_left = cPos.x - Globals.SCREEN_CENTER_X
		c.limit_right = cPos.x + Globals.SCREEN_CENTER_X
		c.limit_top = cPos.y - Globals.SCREEN_CENTER_Y
		c.limit_bottom = cPos.y + Globals.SCREEN_CENTER_Y
		pass
	elif Input.is_action_just_pressed("DebugButton9"):
		if debugDisplay.visible and $CanvasLayer/DebugButtonHelp.visible:
			debugDisplay.visible=false
			$CanvasLayer/DebugButtonHelp.visible=false
		elif debugDisplay.visible:
			$CanvasLayer/DebugButtonHelp.visible = true
		else:
			debugDisplay.visible=true
			
	#No need to set the debug mode flag for this one since it has zero benefit to the player
	#and they can restart by pressing start and down+b anyways
	elif Input.is_action_just_pressed("DebugButton10"):
		die()
	elif Input.is_action_just_pressed("DebugButton12"):
		set_checkpoint(Vector2(),sprite.flip_h)
	
	if Input.is_action_just_pressed("ui_pause"):
		$PauseScreen.updateTimer(timer,timerWithDeath)
		get_tree().paused = true
		$PauseScreen.OnCommand()

#If Android back button pressed
func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		$PauseScreen.updateTimer(timer,timerWithDeath)
		get_tree().paused = true
		$PauseScreen.OnCommand()

func get_input(delta):
	
	if freeRoam:
		velocity.y = 0
		velocity.x = 0
		var m = 3 if Input.is_action_pressed('R1') else 1
		if Input.is_action_pressed('ui_right'):
			velocity.x = 500*m
		if Input.is_action_pressed('ui_left'):
			velocity.x = -500*m
		if Input.is_action_pressed('ui_down'):
			velocity.y = 500*m
		if Input.is_action_pressed('ui_up'):
			velocity.y = -500*m
		#velocity = velocity.normalized() * SPEED
	else:
		#It's here because freeRoam overrides R1
		if Input.is_action_just_pressed("R1"):
			var i = currentWeapon+1
			while true:
				if i == len(Globals.playerData.availableWeapons):
					i=0
				elif Globals.playerData.availableWeapons[i]:
					break
				else:
					i+=1
			currentWeapon=i
			switchWeapon()
		elif Input.is_action_just_pressed("L1"):
			var i = currentWeapon-1
			while true:
				if i < 0:
					i=len(Globals.playerData.availableWeapons)-1
				elif Globals.playerData.availableWeapons[i]:
					break
				else:
					i-=1
			currentWeapon=i
			switchWeapon()
				
		
		var right = Input.is_action_pressed('ui_right')
		var left = Input.is_action_pressed('ui_left')
		var up = Input.is_action_pressed('ui_up')
		var down = Input.is_action_pressed('ui_down')
		var jump = Input.is_action_just_pressed('ui_select')
		var shoot = Input.is_action_just_pressed("ui_cancel")
		if rapidFire and shoot_time > .1:
			shoot = Input.is_action_pressed("ui_cancel")
		
		if Globals.flipButtons:
			jump = Input.is_action_just_pressed('ui_cancel')
			shoot = Input.is_action_just_pressed("ui_select") or rapidFire and (shoot_time > .1 and Input.is_action_pressed("ui_select"))

		
		#Cancel it here instead of accounting for it anywhere else
		#you can move in the split second between Zero falling though the ladder top and grabbing onto
		#the ladder, so cancel it here so they actually snap on correctly
		if (left and right) or movementLocked or grabbingLadder:
			left = false;
			right = false;
			
		#All this shit is copypasted from the example platformer so I have no idea how it works
		# A good idea when implementing characters of all kinds,
		# compensates for physics imprecision, as well as human reaction delay.
		if shoot:
			shoot_time = 0
			if (Globals.playerData.gameDifficulty <= Globals.Difficulty.EASY or bulletManager.get_num_bullets() < 3) and weaponMeters[currentWeapon]>=Globals.weaponEnergyCost[currentWeapon]:
				
				var bi
				var ss
				if sprite.flip_h:
					ss = -1.0
				else:
					ss = 1.0
				#Note: $ is shorthand for get_node()
				#Right here it's doing get_node("bullet_shoot")
				#ternary: var p = 1 if f else -1
				var pos = position + Vector2(73*ss, 10)
				if state == State.ON_LADDER:
					pos = position + Vector2(95*ss, -20)
				
				if currentWeapon!=Globals.Weapons.Buster:
					weaponMeters[currentWeapon]=max(0,weaponMeters[currentWeapon]-Globals.weaponEnergyCost[currentWeapon])
					#print(ceil(weaponMeters[currentWeapon]/128.0*32))
					HPBar.updateAmmo(weaponMeters[currentWeapon]/144.0,false)
				if currentWeapon==Globals.Weapons.Buster:
					bi = bullet.instance()
					
					
					bi.position = pos
					#get_parent().add_child(bi)
					bulletHolder.add_child(bi)
					#KinematicBody2D only
					#bi.linear_velocity = Vector2(800.0 * ss, 0)
					#RigidBody2D only
					bi.init(Vector2(13*ss,0))
				elif currentWeapon==Globals.Weapons.Architect:
					bi = archiRocket.instance()
					bi.position = pos
					#get_parent().add_child(bi)
					bulletHolder.add_child(bi)
					bi.init(int(ss))
				
				add_collision_exception_with(bi) # Make bullet and this not collide
				
				if Globals.playerData.gameDifficulty > Globals.Difficulty.EASY:
					bulletManager.push_bullet(bi)
				else:
					for child in bulletHolder.get_children():
						if is_instance_valid(child) and child.get_class()=="KinematicBody2D":
							#print(child.get_class())
							#child.add_collision_exception_with(bi)
							bi.add_collision_exception_with(child)
					pass
				if sprite.animation=="IdleShoot":
					sprite.frame = 0
				shoot_sprite_time = 0.3
				$ShootSound.play()
		else:
			shoot_time += delta
			
		if jump and is_on_floor():
			#print("Jumped")
			#$FootstepSound.play()
			#state = State.JUMPING
			#if shotTimer.is_stopped():
			#	sprite.set_animation("JumpStart")
			#else:
			#	sprite.set_animation("JumpShoot")
			velocity.y = jump_speed
			state = State.JUMPING
		elif state == State.ON_LADDER:
			#Maybe waste of CPU?
			velocity.y = 0
			#Don't allow moving while shooting
			if up and shoot_sprite_time <=0:
				velocity.y -= 100
			if down and shoot_sprite_time<=0: #and position.y > $Camera2D.limit_bottom+40
				velocity.y += 100
			#Don't allow pressing jump while climbing up the ladder because
			#it creates one frame of the jump animation
			if jump and !up: 
				state = State.FALLING
				sprite.play()
			#This may have been a bad idea
			if left:
				sprite.flip_h = true
			if right:
				sprite.flip_h = false
			
			velocity = velocity.normalized() * SPEED
		#Your normal movement processing
		else:
			if right and position.x < $Camera2D.destPositions[2]-40:
				velocity.x = run_speed
				sprite.flip_h = false
			elif left and position.x > $Camera2D.destPositions[0]+40:
				velocity.x = -run_speed
				sprite.flip_h = true
			elif !movementLocked: #If movement locked, assume velocity should be preserved
				velocity.x=0
			if up:
				var tile = tiles.get_cellv(pos2cell(position))
				if tile == LADDER_TILE_ID or tile == LADDER_TOP_TILE_ID:
					sprite.set_animation("LadderBegin")
					#get position of cell then multiply to get actual character position then offset by half of cell width multiplied by scale
					position.x = pos2cell(position).x*16*4+8*4;
					velocity.x = 0
					#position = Vector2(round(floor(position.x)/16/4)*16*4+8*4, position.y)
					state = State.ON_LADDER
			if down and !movementLocked:
				#print(String()))
				var tilePos = pos2cell(position)
				tilePos.y +=1
				#Get tile underneath you
				var tile = tiles.get_cellv(tilePos)
				var cameraBottom = pos2cell(Vector2(position.x,$Camera2D.limit_bottom))
				#print(String(tilePos.y)+" < "+String(cameraBottom.y)+"?")
				if tile == LADDER_TOP_TILE_ID and tilePos.y < cameraBottom.y: #Don't allow going down on ladders you can't see
					#print("attaching to ladder")
					sprite.set_animation("LadderBegin")
					position.x = pos2cell(position).x*16*4+8*4;
					set_collision_mask_bit(0,false)
					set_collision_layer_bit(0,false)
					#velocity = 
					lockMovement(.05,Vector2(0, 500),false)
					#position = Vector2(round(floor(position.x)/16/4)*16*4+8*4, position.y)
					#grabbingLadder = true
					state = State.GRABBING_LADDER
				#else:
				#	print("Can't go down ladder!")
				#	print(String(tilePos.y)+" < "+String(cameraBottom.y)+"?")
				#	print(String(tile)+"!="+String(LADDER_TILE_ID)+"?")
				#Example for one way platforms (I don't know if 7 is correct)
				#elif tile == 7:
				#	position.x = pos2cell(position).x*16*4+8*4;
				#	#Don't set x velocity since we want them to keep moving at the same rate
				#	velocity.y = 300
				#	set_collision_mask_bit(0,false)
				#	set_collision_layer_bit(0,false)
			if state == State.JUMPING:
				#Cancel upward momentium if jump button is let go
				#I'm pretty sure this can be simplified into one if statement
				if !Globals.flipButtons:
					if velocity.y < 0 and !Input.is_action_pressed("ui_select"):
						velocity.y = 0
						state=State.FALLING
				else:
					if velocity.y < 0 and !Input.is_action_pressed("ui_cancel"):
						velocity.y = 0
						state=State.FALLING
			

		

#The world_to_map function does NOT take into account the scale of the tilemap, so we have to calculate
#the tile's actual mapping ourselves.
onready var tile_scale = get_node("/root/Node2D/TileMap").scale
func pos2cell(pos:Vector2)->Vector2:
	#TODO: Offset is wrong, fix it for real
	#pos minus 30 (why?) divided by quadrant size divided by tile scale
	return Vector2(round((pos.x-32)/16/tile_scale.x), round((pos.y-16)/16/tile_scale.y));

func cell2pos(pos:Vector2)->Vector2:
	return pos*16*tile_scale

#Aka "This will have to be rewritten at some point because the player node is
# not supposed to handle events"
func handleEvents():
	#if movementLocked: #Maybe need an "Allow events while movement locked" boolean
	#	return
	if state==State.INACTIVE:
		return
		
	if eventCheck.is_colliding():
		#print("Event touched!")
		#This is SO going to crash when I turn the collision on for this by accident
		var event = eventCheck.get_collider()
		#Some events don't have ".disabled" for some reason... Yeah...
		if !("event_ID" in event) or ("disabled" in event and event.disabled):
			return
		#assert("event_ID" in collider,"Hey idiot, you have something on the event layer without an assigned ID!")
		var event_ID = event.event_ID
		#print(event_ID)
		match event_ID:
			Globals.EVENT_TILES.NO_EVENT:
				print("This event has not been assigned an ID!")
			Globals.EVENT_TILES.SIGNAL:
				event.signal_event()
				event.disabled=true
			Globals.EVENT_TILES.IN_WATER:
				#print("In water!")
				if !inWater:
					$SplashSound.play()
					var sp = splashAnimation.instance()
					#It's just rounding the y position to the nearest block
					#and then discarding the x position
					sp.position.y = pos2cell(position).y*16*tile_scale.y
					sp.position.x = position.x
					get_parent().add_child(sp)
				inWater = true;
			Globals.EVENT_TILES.OUT_WATER:
				if inWater:
					$SplashSound.play()
					var sp = splashAnimation.instance()
					#Note the +1 here, it's because out of water tiles are above in water
					sp.position.y = (pos2cell(position).y+1)*16*tile_scale.y
					sp.position.x = position.x
					get_parent().add_child(sp)
				inWater = false;
			Globals.EVENT_TILES.MESSAGE_BOX:
				get_tree().paused=true
				event.disabled = true
				var newCutscene = gf_cutscene.instance()
				
				self.add_child(newCutscene) #Needs to be done first for the _ready()
				newCutscene.init_(
					event.message,
					get_parent(),
					true
				)
			Globals.EVENT_TILES.CUSTOM_EVENT:
				event.run_event(self)
			Globals.EVENT_TILES.CHECKPOINT:
				set_checkpoint(event.respawn_position,event.respawn_facing_left)
				event.disabled=true
			_:
				print("Unknown event ID: "+String(event_ID))

func set_checkpoint(respawnPosition:Vector2,shouldFaceLeft=false):
	if respawnPosition != Vector2(0,0):
		CheckpointPlayerStats.lastCheckpointPos = cell2pos(respawnPosition)
	else:
		CheckpointPlayerStats.lastCheckpointPos=position
		var cam = $Camera2D
		CheckpointPlayerStats.lastCameraBounds=cam.destPositions
	#CheckpointPlayerStats.lastHealth=HP
	CheckpointPlayerStats.setTimer(timer)
	CheckpointPlayerStats.lastWeaponMeters=weaponMeters
	print("Set new respawn position to"+String(CheckpointPlayerStats.lastCheckpointPos))
	print("Set the camera parameters to "+String(CheckpointPlayerStats.lastCameraBounds))
	
	CheckpointPlayerStats.shouldFaceLeft=shouldFaceLeft
	CheckpointPlayerStats.checkpointSet=true

func _physics_process(delta):
	if !is_timer_stopped:
		timer+=delta
		timerWithDeath+=delta
	
	#Needs to be done first to check is_on_floor() properly
	velocity = move_and_slide(velocity, Vector2(0, -1), true)
	velocity.y = min(velocity.y,1500) #Cap the fall speed
	
	
	
	if shoot_sprite_time > 0:
		shoot_sprite_time -= delta
	
	#Menu buttons should always be accessible!
	get_menu_buttons_input(delta)
	
	if state==State.INACTIVE:
		sprite.visible=false
		invincible=true
		velocity.y += gravity * delta
		stateInfo.text = sprite.get_animation() + " ! " + String(sprite.is_playing())
		time_before_active-=delta
		if time_before_active<=0:
			sprite.visible=true
			if !sprite.playing:
				sprite.playing=true
			elif sprite.frame==3:
				state=State.NORMAL
				invincible=false
		return
	elif not movementLocked:
		get_input(delta)
		handleEvents() #This modifies velocity
		
	if position.x < $Camera2D.limit_left+10:
		#velocity.x=run_speed
		position.x+=3
	
	var tile = tiles.get_cellv(pos2cell(position))
	#I got tired of dying to spikes in free roam
	if tile == SPIKES_TILE_ID and (not noClip and not freeRoam) and not invincible:
		die()
	elif tile == DEATH_TILE_ID and (not noClip and not freeRoam):
		die()
	
	#Only process when moving or falling. Because otherwise the character slides down slopes and that's bad.
	#if !is_on_floor():
	#velocity.y = gravity
	if not freeRoam and state != State.ON_LADDER:
		if inWater:
			velocity.y += gravity/2 * delta
		elif inSand:
			velocity.y += gravity * 4 * delta
		else:
			velocity.y += gravity * delta
	
	if state==State.FLYING_BACKWARDS:
		velocity.y=0
		if is_on_wall():
			invincibleTime=0
			$Camera2D.shakeCamera(10.0)
			clearLockedMovement()
			velocity.y = 200
			if sprite.flip_h:
				velocity.x = -300
			else:
				velocity.x = 300
			lockMovement(.25,velocity,false)
			state=State.FALLING

	if is_on_floor() and velocity.y >= 0:
		if state == State.FALLING:
			footstep.play()
		state = State.NORMAL
			
		if velocity.x != 0:
			if shoot_sprite_time <= 0:
				if sprite.animation == "WalkLoopShoot":
					var prevFrame = sprite.get_frame()
					sprite.set_animation("WalkLoop")
					sprite.set_frame(prevFrame)
				else:
					sprite.set_animation("WalkLoop")
			else:
				if sprite.get_animation() == "WalkLoop":
					var prevFrame = sprite.get_frame()
					sprite.set_animation("WalkLoopShoot")
					sprite.set_frame(prevFrame)
				elif sprite.get_animation() != "WalkLoopShoot":
					sprite.set_animation("WalkLoopShoot")
			
			#if sprite.frame == 3 or sprite.frame == 8:
			#	if !$FootstepSound.playing:
			#		$FootstepSound.play()
		else:
			if shoot_sprite_time <= 0:
				sprite.set_animation("Idle")
			elif sprite.animation != "IdleShoot":
				sprite.set_animation("IdleShoot");
	elif state == State.GRABBING_LADDER:
		if tile == LADDER_TILE_ID or tile == LADDER_TOP_TILE_ID:
			state = State.ON_LADDER
	elif state == State.ON_LADDER:
		#jumping = false
		#ez modo way of playing the ladder animation
		#Wait for begin animation to be done
		if sprite.get_animation() == "LadderBegin":
			if sprite.frame == sprite.frames.get_frame_count("LadderBegin")-1:
				sprite.set_animation("LadderLoop")
			
		elif shoot_sprite_time > 0:
				#TODO: Change to shot animation while keeping the frame
				#var prevFrame = sprite.frame
				sprite.set_animation("LadderShoot")
				#elif sprite.animation == "IdleShoot":
				#	sprite.frame=0
		else:
			sprite.set_animation("LadderLoop")
		
		if sprite.get_animation() == "LadderLoop":
			# TODO: This isn't correct. Her animation should
			# be tied to her y position.
			if abs(velocity.y) > .1:
				sprite.play()
			else:
				sprite.stop()
			
		if tile != LADDER_TILE_ID and tile != LADDER_TOP_TILE_ID:
			state = State.FALLING
			if tile != LADDER_TOP_TILE_ID and velocity.y < 0:
				#TODO: So..... This doesn't work if you move the collision box 
				lockMovement(.2,Vector2(velocity.x,-350),true)
				sprite.set_animation("LadderFinish")
				sprite.play()
			else:
				#state = State.FALLING
				sprite.set_animation("Falling")
				
	elif velocity.y > 0.5 and not movementLocked:
		state = State.FALLING
		
	if !is_on_floor() and not movementLocked and state != State.ON_LADDER:
	#if state == State.FALLING:
		if shoot_sprite_time <= 0:
			sprite.set_animation("Falling")
		else:
			sprite.set_animation("FallingShoot")
	
	#only update this if the display is showing
	if debugDisplay.visible:
		stateVelocity.text = String(velocity * delta)
		#stateInfo.text=String(bulletManager.get_array_as_int())
		#stateInfo.text=String(bulletManager.get_raw_bullet_pos(0))
		#stateInfo.text=String(bulletManager.is_bullet_onscreen(0))+" "+String(bulletManager.get_onscreen_bullet_pos(0))
		#stateInfo.text = state_toString[state] + " "+sprite.get_animation()
		#stateInfo.text = "On floor? " + String(self.is_on_floor())
		#stateInfo.text = "Touching wall and NOT floor? " + String((is_on_wall() and !is_on_floor()))
		#stateInfo.text = "Floor: " + String(is_on_floor()) + " Wall: " + String(is_on_wall()) + " Ceiling: " + String(rayCast.is_colliding())
		#stateInfo.text = "Floor:" + String(is_on_floor()) +" ! "+ "Jumping: "+String(jumping)
		stateInfo.text = sprite.get_animation() + " ! " + String(sprite.is_playing())
		if Globals.playerData.gameDifficulty > Globals.Difficulty.EASY:
			for i in range(3):
				stateInfo.text +="\n"+String(bulletManager.get_onscreen_bullet_pos(i))
		
		#stateInfo.text = "InWater? "+ String(inWater)
		#stateInfo.text = String(invincible)
		var cell = pos2cell(position)
		
		statePos.text = String(stepify(position.x,.01)) + ", " + String(stepify(position.y,.01))
		stateTile.text = String(tile) + " ! "+String(pos2cell(position)) + " ! " + String(cell.x*16*4+8*4) +","+ String(cell.y*16*4+8*4)
		#jumping = true
		#stateTile.text = "Jumping? " + String(jumping)
		#stateTile.text = String(get_collision_mask_bit(0)) + " " + String(get_collision_mask_bit(0))
		cameraInfo.text = "L: "+String($Camera2D.limit_left)+" R: "+String($Camera2D.limit_right)
		cameraInfo.text += "\nT: "+String($Camera2D.limit_top)+" B: "+String($Camera2D.limit_bottom)
		var cPos = $Camera2D.get_camera_screen_center()
		cameraInfo.text += "\nOffset: "+String($Camera2D.offset)+ "\nPos: "+String(stepify(cPos.x,.01)) + ", " + String(stepify(cPos.y,.01))
		
		onscreenPos.text = "Onscreen pos: " + String(stageRoot.position + position + stageRoot.get_canvas_transform().origin)
		
	
	if movementLocked:
		processLockMovement(delta)
		
	if invincible:
		processInvincible(delta)
		
	#If collision is turned off we've already processed the movement so now we can turn it back on
	#But don't turn it back on if noClip is on
	if !get_collision_mask_bit(0) and !noClip and !movementLocked:
		set_collision_mask_bit(0,true)
		set_collision_layer_bit(0,true)

#Should this be using structs?
var movementLocked = false
var timeElapsed:float = 0.0
var lockQueue = []
var posInQueue:int = 0

func lockMovement(time:float,velocity:Vector2,freeze_y_velocity:bool=true):
	lockMovementQueue([[time,velocity,"",freeze_y_velocity]])

#Queue is structured like time,vector2,animation,freeze_y_velocity
#obj.call("lockMovementQueue",[
#	[.3,Vector2(0,0)],
#	[.5,Vector2(obj.run_speed,0),"",false],
#	[.3,Vector2(0,0),"Idle"]
#])
func lockMovementQueue(queue:Array):
	lockQueue = queue
	movementLocked = true
	velocity=queue[0][1]
	
#You can see that x velocity is only being set once if queue[x][3] is false,
#That's because the above processing code checks if movement is locked
#And preserves the x velocity
func processLockMovement(delta):
	timeElapsed += delta
	#var n = len(lockQueue[posInQueue])
	if timeElapsed > lockQueue[posInQueue][0]:
		if posInQueue == len(lockQueue)-1:
			clearLockedMovement()
		else:
			posInQueue+=1
			timeElapsed = 0.0
			velocity=lockQueue[posInQueue][1]
			if len(lockQueue[posInQueue])>2 and lockQueue[posInQueue][2]!="":
				sprite.set_animation(lockQueue[posInQueue][2])
	elif len(lockQueue[posInQueue])>3 and lockQueue[posInQueue][3]:
		velocity=lockQueue[posInQueue][1]

func clearLockedMovement():
	posInQueue=0
	timeElapsed=0.0
	movementLocked = false
	


var invincible = false
var invincibilityElapsed = 0.0
var invincibleTime = 0.0
func processInvincible(delta):
	invincibilityElapsed += delta
	if invincibilityElapsed > invincibleTime:
		invincible = false
		invincibilityElapsed = 0.0
		sprite.modulate.a = 1
		#$FuckGodot.set_deferred("monitorable",true)
		#$FuckGodot.set_collision_mask_bit(0,true)
		#$FuckGodot.set_collision_layer_bit(0,true)

func player_touched(obj, amountToDamage:int):
	if !invincible:
		#$FuckGodot.set_deferred("monitorable",false)
		#$FuckGodot.set_collision_mask_bit(0,false)
		#$FuckGodot.set_collision_layer_bit(0,false)
		if state != State.ON_LADDER:
			if is_on_floor():
				velocity.y = -200
			else:
				velocity.y = 200
				
			if sprite.flip_h:
				velocity.x = 300
			else:
				velocity.x = -300
			lockMovement(.25,velocity,false)
		if Globals.playerData.gameDifficulty == Globals.Difficulty.HARD:
			amountToDamage*=1.5
		elif Globals.playerData.gameDifficulty == Globals.Difficulty.SUPERHERO:
			amountToDamage*=2.0
		HP-=amountToDamage;
		if HP > 0:
			HPBar.updateHP(HP)
			$HurtSound.play()
			sprite.set_animation("Hurt")
			sprite.modulate.a = .5
			
			Input.start_joy_vibration(0,.5,.3,.1)
			
			invincibleTime = 1
			invincible = true
		else:
			die()

# -1 = based on player facing, 0 = left, 1 = right, 2 = down, 3 = up
func player_send_flying(obj,amountToDamage,direction=-1):
	if !invincible:
		HP-=amountToDamage;
		if HP > 0:
			HPBar.updateHP(HP)
			$HurtSound.play()
			sprite.set_animation("Hurt")
			sprite.modulate.a = .5
			if direction==-1:
				if sprite.flip_h:
					velocity.x = 950
				else:
					velocity.x = -950
			elif direction==0:
				velocity.x=-950
				sprite.flip_h=false
			lockMovement(999,Vector2(velocity.x,0),true)
			invincibleTime = 999
			invincible=true
			state = State.FLYING_BACKWARDS
		else:
			die()
			
var isDead = false
func die():
	if isDead == false:
		isDead = true
		$CanvasLayer/Timer.set_process(false)
		CheckpointPlayerStats.setDeathTimer(timerWithDeath)
		set_physics_process(false)
		HP = 0
		HPBar.updateHP(HP)
		CheckpointPlayerStats.playerLivesLeft-=1
		sprite.visible = false
		
		var sp = deathAnimation.instance()
		sp.position=position-Vector2(48,16)
		get_parent().add_child(sp)
		$DieSound.play()
		yield($DieSound,"finished")
		$CanvasLayer/Fadeout.fadeOut()
		yield($CanvasLayer/Fadeout/Fadeout_Tween,"tween_completed")
		if Globals.playerData.gameDifficulty < Globals.Difficulty.MEDIUM or CheckpointPlayerStats.playerLivesLeft >= 0:
# warning-ignore:return_value_discarded
			get_tree().reload_current_scene()
		else:
# warning-ignore:return_value_discarded
			get_tree().change_scene("res://TitleScreenV2.tscn")

func finishStage():
	is_timer_stopped=true
	CheckpointPlayerStats.setDeathTimer(timerWithDeath)
	CheckpointPlayerStats.setTimer(timer)
	lockMovement(999,Vector2(),false)
	get_node("/root/Node2D").stopMusic()
	$VictorySound.play()
# warning-ignore:return_value_discarded
	$VictorySound.connect("finished",self,"finishStage_2")
	
func finishStage_2():
	$CanvasLayer/Fadeout.fadeOut()
	yield($CanvasLayer/Fadeout/Fadeout_Tween,"tween_completed")
	var nextScene = "res://ItemGet/ItemGet.tscn"
	CheckpointPlayerStats.lastPlayedStage = stageRoot.weapon_to_unlock
	if Globals.playerData.availableWeapons[stageRoot.weapon_to_unlock]: #If this stage is already completed
		nextScene="res://StageSelectV2/NewBossSelect.tscn"
	Globals.playerData.availableWeapons[stageRoot.weapon_to_unlock]=true
	Globals.save_player_game()
# warning-ignore:return_value_discarded
	get_tree().change_scene(nextScene)
	

func healPlayer(amount):
	HP = min(HP+amount,MAX_HP)
	HPBar.updateHP(HP,true)
	#print(HP)
	#$HealSound.play()
	#$HealAnimation.frame = 0
	#$HealAnimation.play()
	
func restoreAmmo(amount):
	#Right now there's only one weapon so let's just pretend...
	weaponMeters[1]=min(144,weaponMeters[1]+amount)
	if currentWeapon!=0:
		HPBar.updateAmmo(weaponMeters[currentWeapon]/144.0,true)
	
func giveExtraLife():
	if Globals.playerData.gameDifficulty < Globals.Difficulty.MEDIUM:
		HP = MAX_HP
		HPBar.updateHP(HP,false)
	else:
		CheckpointPlayerStats.playerLivesLeft+=1
	$OneUpSound.play()
