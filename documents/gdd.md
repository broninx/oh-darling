# Oh Darling (prototype for now)

## Overview and vision statement

Oh Darling is an abstract, narrative-driven RPG where you play as a bipolar protagonist trapped in a world that reflects your fractured mind. Blending the deep psychological introspection of Disco Elysium with visual novel romance elements, it is a game about the terrifying tension between acting on what feels "personally right" and fighting to maintain your own sanity.

Our vision is to create a highly immersive, uncompromising psychological experience that challenges traditional concepts of difficulty, morality, and narration. Oh Darling grants the player freedom through a highly reactive world governed by dialogue and emotional consequence. The core fantasy is not one of empowerment, but of survival and self-discovery; the player must navigate a deeply unreliable reality, decode their own hidden emotional states, and grapple with the permanent consequences of their fractured psyche.

## Gameplay

### Gameplay Overview and Intent

The gameplay is heavily inspired by *Disco Elysium*, placing dialogue and psychological introspection at the core of the player experience. While the player character can navigate the world and interact with the environment, the vast majority of interactions with characters, items, and the world occur through dialogue.

The gameplay loop emphasizes the tension between acting on what feels temporarily "personally right" (which deepens psychosis and potentially undesired gameplay elements) and acting conservatively (which stabilizes the character at a cost). 

### Core Gameplay Loop

The moment-to-moment gameplay revolves around a continuous cycle of exploration, dialogue, and psychological management.

1. **Exploration:** The player navigates the world using point-and-click mouse and keyboard controls, discovering interactive elements, NPCs, and time-gated events.
2. **Dialogue & Interaction:** The player engages in deep, branching dialogues with NPCs. 
3. **Psychological Impact:** Dialogue choices and interactions alter hidden emotional states and advance the in-game clock.
4. **State Management:** The player observes their environment (which changes based on their mental state) and makes subsequent choices to either maintain their current state or try to intentionally shift it.
5. **Consequence:** NPC schedules, available dialogue options, and environmental perception shift based on the passage of time and the player's current emotional state. 

### Systems and Features

#### Time Management System

The game features a dynamic time progression system where the in-game clock advances **exclusively** during NPC dialogues and specific narrative interactions. 

* **Pacing:** Each in-game day lasts approximately **20 to 40 minutes** of real-time gameplay, depending on the player's reading speed.
* **NPC Schedules:** The world operates on a strict schedule. NPCs have specific daily routines, and available interactions are time-locked (e.g., the bar is open from 7:00 to 12:00; homeless NPCs are always at their resting spots at night).
* **Scarcity and Consequence:** The game is designed so the player cannot "do everything all at once." Similar to *Pathologic 2*, the player's schedule is limited. Choosing to progress a subquest with one NPC alters the player's interaction with another. These choices have serious, delayed consequences that the player observes later in their experience.
* **Intent:** To create a sense of urgency, force meaningful narrative choices, and make the world feel alive and independent of the player.

#### The Emotion System (Hidden Variables)

The game stores a set of hidden values representing primitive emotional "states" or "moods." The player is never explicitly shown these numbers; instead, they must decode their current state by observing symptoms in the world and the protagonist's behavior.

* **Dynamic Alteration:** These hidden emotional states are continuously altered by the player's dialogue choices and reactions to game events.
* **Gameplay Effects:** Due to the protagonist's extreme emotional instability, these states heavily influence multiple game systems:
  * **Visuals and Perception:** Emotional states dictate the graphical style of the game via shaders, HSL shifts, texture changes, and environmental shifts. Extreme states trigger hallucinations known as **"Echoes."** *(See [Art Style](#art-style).)*
  * **Dialogue Choices:** Extreme emotional states "lock" dialogue options that contradict the player's current state. Conversely, certain unique interactions are only available while in specific emotional states.
  * **Procedural Audio:** The soundtrack is built using a layered stem system. The volume and intensity of specific instrumental stems change dynamically based on the player's hidden emotional state.

#### Distortion (Psychosis)

When the player's hidden emotional states are pushed to extreme limits (shifting towards specific far ends of their respective spectrums), the protagonist enters a state of **Distortion** (Psychosis).

* **Mechanic:** Distortion is a survival system. The more the player makes choices that feel "personally right" to the character, the deeper they fall into Distortion. Conversely, acting instinctively and illogically (or logically, if for the better) stabilizes the character.
* **Consequences:** Distortion causes severe negative gameplay consequences. However, it is a natural and intended part of the narrative arc. Reaching Distortion fundamentally alter familiar game elements (making them untrustworthy) and warps the player's perception of reality. 
* **Intent:** To subvert traditional "min-maxing" game mechanics. Emotions are meant to be explored, and the player must navigate the tension between morality and mental survival without the safety net of save-scumming (the game features **Autosave only**; every choice is permanent).

## Progression and Narrative Flow

*[Link to Player Objectives and Progression section]*

Progression is non-linear and driven entirely by the management of the aforementioned systems. A "level" in *Oh Darling* is not a physical space, but a narrative scene, a conversation, or an internal moment. Early scenes are grounded and reliable. As the protagonist's emotions shift and Distortion rises, the gameplay transforms: text becomes unreliable, the meaning of words shifts dynamically, and the NPC's behavior evolves based on the protagonist's state.


## Characters

* **The Protagonist (Main Character)** <br>
Raised by a mother who over-validated them, they possess a brilliant brain and a keen eye for detail, but suffer from extreme stubbornness that fuels obsessive thoughts. They come to town after a series of life-altering events caused by a psychotic episode: their marriage collapsed because their partner couldn't handle the intensity of it, they were fired from their previous job for causing a scene and their doctor forced them back onto medication. Now, they hold a position as the Town Hall's archivist and are ready to rebuild their life. However, the quiet archive that was supposed to cater to their need for stability and routine also grants them access to the town's sensitive information, which might ignite and fuel their paranoia into insane conspiracies.

* **Chris MacLean (The Respectable Mayor)** <br>
A charismatic, wildly popular leader who gentrified the town and built its famous and successful farmers' market. However, his entire legacy is built on a grotesque, closely guarded secret: to secure the land for the market, he exploited a bizarre database glitch to legally marry a prize-winning truffle pig that had inherited a massive estate from an eccentric countess. On the surface, he displays a fun and endearing demeanor despite his well-known perfectionism; however, he shows no mercy in suppressing anyone who threatens his reputation and position.

* **Jolly Roger (Mad Clochard)**<br>
Once an archivist and the Mayor's right-hand man, Roger discovered the truth about the Mayor's marriage, which led to his disastrous downfall at the Mayor's hands. Desperation and the abuse of recreational substances have reduced him to acting like an unreasonable, crazed man. Knowing the actual source of the town's prosperity, he believes all of the MC's crazy theories and serves as their main enabler.

* **Neha Sharma (The Neon Padma's Owner)** <br>
An inherently nurturing woman of Indian descent who endured a painful divorce after discovering her infertility. She channels her maternal instincts into her business and charity work. Taught botanical history and tea brewing by her *Dadima*, she built a successful career as a mixologist; however, the fast-paced city life eventually prompted her to move to this town. Highly perceptive and spiritually grounded, she provides the only genuinely stable, non-toxic environment in the game, despite her undying curiosity about whatever happens in people's lives. If the MC is able to earn her trust, she will share very interesting stories. She easily notices the MC's increasingly unusual behavior and frequently offers them a calming solution from her personal recipe book.

* **The PR Agent (Female Love Interest)**<sup>a</sup> <br>
Ambitious, magnetic and deeply manipulative. She has a history of ending relationships perfectly, leaving her exes with fond memories while she extracts exactly what she needs. She aims to climb the political ladder by uncovering the town elite's dirt. She deliberately acts as an emotional mirror for the MC, providing the unconditional validation the MC craves. Instead of grounding the MC, she maliciously encourages and enables their paranoid delusions ("You're the only one smart enough to see the truth"), pushing them toward a psychotic break just to extract the archive secrets she needs for her career, with total disregard for the MC's well-being.

* **The Head Contractor (Male Love Interest)**<sup>a</sup> <br>
Reliable, protective and deeply codependent. He has a history of playing the indispensable hero, keeping his partners helpless and subtly clipping their wings until they inevitably outgrow him. He aims to secure his own self-worth by being the sole protector of a fragile partner. He deliberately acts as an immovable rock for the MC, infiltrating their strict routine and providing the absolute physical safety they crave. Instead of validating the MC's genuine discoveries, he maliciously employs a "well-meaning" form of gaslighting to keep the peace ("Your beautiful brain works too hard. Leave the dark thoughts outside."), pushing them toward a complete loss of self-trust just to ensure they remain entirely dependent on him, with total disregard for the MC's intellectual autonomy.

<sup>a</sup>: Love Interests are meant to be two faces of the same coin, this explains the strict parallelism into describing them.
## Story
The game’s narrative approach is intentionally deceptive. It begins as a methodical slice-of-life simulator, focusing entirely on the protagonist's strict daily routine, their new job as an archivist and the mundane interactions with the town's quirky but seemingly harmless residents. In these early stages, there is no overarching "plot" other than the MC’s personal struggle to rebuild their life after a psychotic episode, alongside uncovering minor, everyday subplots about the other characters. However, as the game progresses and the MC’s mental state begins to deteriorate, a macabre narrative begins to take control.<br>
The MC slowly convinces themselves that the town’s pristine beautyand its wildly successful farmers' market are not the results of good governance, but the dark blessings of a pagan cult dedicated to [**Freyr, the Norse God of Prosperity and Agriculture**](https://immagina.re/biblioteca-norrena/rituali/invocazione-a-freyr) and the town is a modern recreation of the infamous [Temple of Uppsala](https://en.wikipedia.org/wiki/Temple_at_Uppsala).<br>
Piece by piece, the protagonist connects harmless town elements to gruesome historical lore and what begins as a quiet game about managing trauma and organizing archives spirals into a claustrophobic psychological horror. The player must navigate a world where it becomes difficult to distinguish between the MC's delusions and the reality around them, and has to figure out a way out.

## World
The game takes place in a town with a rustic charm to it, where old brick facades are sandblasted and spotless, public parks are lush and mathematically manicured. Everything seems so pristine without a single chipped brick or flickering streetlamp, reflecting the Mayor's obsessive perfectionism.
The famous farmers’ market isn’t a chaotic, it’s an upscale exhibition. Local farmers arrive to peddle their overpriced produce from colorful, inviting stalls carefully designed to give off a nostalgic, "*freshly baked pie*" vibe. The air always smells faintly of fresh lavender, artisan sourdough and expensive coffee.
They possess the relaxed, smug aura of people who know they’re living the dream. Their devotion to the Mayor borders on a cult of personality, creating a suffocating positivity where complaints are treated as social faux pas.

### Key Locations
* **The Protagonist's House**<br>
The interior is designed with neutral decorations and colors to avoid overstimulation, integrating calming details such as potted plants. Heavy curtains act as a crucial element to mitigate the character's paranoia (the intense fear of being watched), allowing them to close off the outside world to gain a sense of protection. The exterior of the house conforms perfectly to the pristine, manicured image of the town enforced by the Mayor.

* **The Park and the Shelter**<br>
The public park features a beautifully maintained children's playground, surrounded by a walkable, curated forest. Deep within this woods, however, lies an extremely messy and chaotic shelter (Roger's shelter). The surrounding area is littered with abandoned sculptures made entirely of junk and scrap materials. Among these stands a peculiar pig-shaped sculpture, ironically identified as the "town's savior".

* **The Neon Padma**<br>
The bar features a welcoming interior design, characterized by warm wooden elements and hanging glass lamps. During the day, the atmosphere is calm and bright, perfect for serving breakfast goods. At night, the venue transitions into a moody and slightly mysterious vibe focused on cocktails and snacks. The walls are adorned with traditional mandalas that appear as standard colorful decorations by day, but light up with modern neon accents after dark.

* **The Town Hall & Archives**<br>
Recently redeveloped under the Mayor's obsessive eye, the Town Hall displays a spotless and gentrified facade. The upper floors are constituted of perfectly lit offices, where the Mayor's and his collaborators work. In stark contrast, the basement houses the quiet and dusty archives.

### World Map

The open map is a compact town where every location is accessible and interactable, with no filler spaces.
Every location has its own opening and closing hours: stores, homes, the pub, the park, and the Town Hall alike. A place is only accessible while it is open, or, in the case of homes, while the resident is in, so the player must plan each visit around the schedule *(see [Time Management System](#time-management-system))* and accept that some places will be closed when they need them.

| Location | Description | 
| --- | --- |
| Town Hall | Seat of the Mayor's authority and the protagonist's workplace, where they serve as archivist. 
| Town Square | The civic heart of the town, home to the farmers' market and public gatherings. |
| The Neon Padma | A warm, wood-and-glass pub: a bright breakfast spot by day, a moody cocktail bar by night, with mandalas that glow neon after dark. |
| The Park | Lush, mathematically manicured greenery in perfectly defined areas. |
| Main Character's Home | The protagonist’s home: spotless outside like the rest of the town, calm inside, with neutral decor, plants to tend as a routine, and heavy curtains to close out the world. |
| Stores| The town's shops line the streets around the square. Like everything else, they are immaculate, themed, and run by owners who treat the Mayor's standards as a point of pride.
| NPC Homes | The residences of the town's characters, scattered through its streets.|  

#### The Margins

A town without imperfections must hide them somewhere. Residents who live outside the Mayor's order, such as the homeless, occupy the margins the town's perfection does not reach. They show what the community has quietly pushed out, and they are natural sources of honest dialogue for a protagonist who does not fit in either.


### Art Style

The hidden emotional states are shown visually through five moods, named after the weather. Fog is the lowest, Storm the highest, and Clear is the balanced middle. The places and characters stay the same, but how they are painted changes, and in the extreme moods the world itself starts to change too.

| Mood | What the protagonist feels | How the world feels |
| --- | --- | --- |
| Fog | Very low mood, no interest in anything, guilt, exhaustion. Daily life stops | Distant, heavy, empty |
| Overcast | Low mood, little interest and little energy. Daily life goes on, with effort | Everything is normal, but something is missing |
| Clear | Balanced mood, the baseline | Reliable and a little melancholic |
| Bright | High mood and growing energy, still under control | Everything shines, everything seems possible |
| Storm | Euphoria or irritability, racing thoughts, little sleep, feeling unstoppable | Too much colour, too much movement, too much of everything |

Each mood has its own painterly style, inspired by a period of art history.

| Mood | Style | Reference | Palette | Brushwork and light |
| --- | --- | --- | --- | --- |
| Fog | Faded expressionism | Schiele, Picasso (Blue Period) | Blues and greys, almost monochrome | Broken lines, cold light |
| Overcast | Silent interiors | Hammershøi | Warm greys, off-whites | Smooth brushwork, dim light |
| Clear | Painterly realism | Disco Elysium | Ochre, olive green, dusty blue | Calm brushwork, natural light |
| Bright | Luminous impressionism | Monet, Renoir | Yellows, pinks, light blues | Short dabs, golden light |
| Storm | Swirling post-impressionism | Van Gogh | Chrome yellow, ultramarine, orange | Swirling impasto, dazzling light |

All moods share the same base. Environments and characters are in 3D, a shader gives them a painted look, and the camera is isometric. Only in the extreme moods does the camera change: in Storm it sways slightly, and in Fog it pulls back, making the protagonist look small.

#### Visual Distortion

In Fog and Storm, Distortion *(see [Distortion](#distortion-psychosis))* also changes how the scene looks, from small anomalies to a room that sways or tilts.

#### Echoes

Echoes are things the player sees that aren't really there: the world reflects back what the protagonist feels. In Storm they are grandiose and everything revolves around the protagonist: golden lights, rays pointing at them, people looking at them with admiration. In Fog they are threatening or guilt-inducing: presences at the edges of the room, faces turning away, objects that seem to accuse.

#### Sensitive Objects

Some key objects, such as the window, the mirror and the door, change with the mood. In Overcast and Bright the object stays the same, but its meaning changes: what stands out, how it is described and which actions it offers. In Fog and Storm the object shows an Echo.

#### Staging Rule

An object never changes while the player is looking at it. The swap happens when it leaves the frame or after a dialogue, so the player is never sure what they saw before.

## Technical specification (if applicable)

## Team
1. Matteo Bellino
2. Franco Antonini
3. Daniel Lazzarotto
4. Alba Suli
5. Gaia Vizza
