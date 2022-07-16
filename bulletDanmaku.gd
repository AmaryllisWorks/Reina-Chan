extends "res://Stages_Reina/Enemies/bulletDinergate.gd"
#BulletDanmaku - It's like a bullet but COOLER

export(int,"normal","reverse_x_pos","spread_x_pos") var special_type=0
export(float,0.1,2,.1) var time_to_reverse = 1
export(float,0.0,0.5,.01) var reverse_time_increase=0.0

#xpos,velocity
export(Vector2) var destination_spread_xpos = Vector2(0,1)
#export(float,0.0,0.5,.01) var slowdown_speed=0.0
#export()
export(Vector2) var CubicSpread = Vector2(0,0)

#//Stolen from RageUtil
#/**
# * @brief Scales x so that l1 corresponds to l2 and h1 corresponds to h2.
# *
# * This does not modify x, so it MUST assign the result to something!
# * Do the multiply before the divide to that integer scales have more precision.
# *
# * One such example: SCALE(x, 0, 1, L, H); interpolate between L and H.
# */
static func SCALE(x:float, l1:float, h1:float, l2:float, h2:float)->float:
	return (((x) - (l1)) * ((h2) - (l2)) / ((h1) - (l1)) + (l2))

#Returns within range of 0 to 1
static func Flip(x:float)->float:
	return 1.0-x

#Returns within range of 0 to 1
static func EaseOut(t:float)->float:
	return Flip(pow(Flip(t),2))


var startingPos_x:float=0.0
func init(t_movement):
	DAMAGE_AMOUNT=2
	startingPos_x=self.position.x
	movement = t_movement
	# warning-ignore:return_value_discarded
	$Area2D.connect("body_entered",self,"objectTouched")
	if timer < 0.0:
		set_process(true)
		self.visible=false
	else:
		set_physics_process(true)

var timer:float = 0.0
const FLOAT_MAX = 1.79769e308
func _physics_process(delta):
	
	#This can also be used to make bullets rebound,
	#but that's probably not what you want.
	#movement+=CubicSpread
	#CubicSpread+=CubicSpread
	movement+=CubicSpread*delta
	
	if special_type==1:
		if timer>=time_to_reverse:
			movement.x*=-1
			time_to_reverse+=reverse_time_increase
			timer=0
	elif special_type==2:
		if timer<destination_spread_xpos.y:
			#I don't think the full SCALE func is needed for this but 
			#math is extremely cheap for the CPU anyways
			var timeScaled:float = SCALE(timer,0,destination_spread_xpos.y,0,1)
			self.position.x=startingPos_x+EaseOut(timeScaled)*(destination_spread_xpos.x-startingPos_x)

		pass
	#._physics_process(delta)
	timer+=delta

func _process(delta):
	timer+=delta
	if timer >=0:
		self.visible=true
		set_process(false)
		set_physics_process(true)
