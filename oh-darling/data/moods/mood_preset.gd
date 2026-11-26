# ==============================================================================
#  MOOD PRESET  (task T05)
# ==============================================================================
#  TASK
#    The weather of ONE mood. There is one .tres file for each mood, in
#    data/moods/. The file name is the mood name: fog.tres, overcast.tres,
#    clear.tres, bright.tres, storm.tres.
#    The EnvironmentController reads these files. It tweens the values when
#    the mood changes.
#
#  HOW TO ADD A VALUE
#    Add an @export here, give it a "no effect" default, and add it to
#    EnvironmentController._apply(). Then set it in the .tres files.
#
#  NOW
#    Fog, rain and lightning. Other values (light, camera) come later.
# ==============================================================================
class_name MoodPreset
extends Resource
## The weather values of one mood. Read by EnvironmentController.

## The mood name. It must be the same as the file name.
@export var mood: String = ""

@export_group("Fog")
## Depth fog. 0 turns the fog off. The camera is about 37 m from the player,
## so small values already show.
@export_range(0.0, 0.1, 0.001) var fog_density: float = 0.0
## The colour of the depth fog.
@export var fog_light_color: Color = Color(0.52, 0.55, 0.61)
## Below this height (world Y, metres) the fog gets thicker.
@export_range(-10.0, 20.0, 0.1, "suffix:m") var fog_height: float = 0.0
## How much thicker the fog gets below fog_height. 0 = no height fog.
@export_range(0.0, 2.0, 0.01) var fog_height_density: float = 0.0

@export_group("Volumetric fog")
## Fog that the lamps light up (halos). 0 turns it off. It costs GPU time.
@export_range(0.0, 0.2, 0.001) var volumetric_fog_density: float = 0.0
## The colour of the volumetric fog.
@export var volumetric_fog_albedo: Color = Color(1, 1, 1)

@export_group("Rain")
## How much rain: 0 = no rain, 1 = all the drops of the Rain node.
@export_range(0.0, 1.0, 0.01) var rain_amount: float = 0.0

@export_group("Lightning")
## Flashes of light at random times. Only outside (in the rain area).
@export var lightning_enabled: bool = false
## The shortest time between two flashes.
@export_range(1.0, 60.0, 0.5, "suffix:s") var lightning_interval_min: float = 5.0
## The longest time between two flashes.
@export_range(1.0, 60.0, 0.5, "suffix:s") var lightning_interval_max: float = 14.0
## The brightness of a flash.
@export_range(0.0, 16.0, 0.1) var lightning_energy: float = 4.0
