# Oh Darling (prototype for now)

## Overview and vision statement

## Gameplay

### Gameplay Overview and Intent

*Oh Darling* is an abstract, narrative-driven RPG with visual novel romance elements. The gameplay is heavily inspired by *Disco Elysium*, placing dialogue and psychological introspection at the core of the player experience. While the player character can navigate the world and interact with the environment, the vast majority of interactions with characters, items, and the world occur through dialogue.

**Intent:** The primary goal of the gameplay design is to create a highly immersive experience that challenges traditional concepts of difficulty and narration. Instead of relying on combat or twitch-based skills, *Oh Darling* grants the player freedom through a highly interactive and reactive world. The gameplay loop emphasizes the tension between acting on what feels temporarily "personally right" (which deepens psychosis and potentially undesired gameplay elements) and acting conservatively (which stabilizes the character at a cost). 

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
* **Scarcity and Consequence:** The game is designed so the player cannot "do everything all at once." Similar to *Pathologic 2*, the player's schedule is limited. Choosing to progress a subquest with one NPC inevitably alter the player's interaciton with another. These choices have serious, delayed consequences that the player observes later in their experience.
* **Intent:** To create a sense of urgency, force meaningful narrative choices, and make the world feel alive and independent of the player.

#### The Emotion System (Hidden Variables)

The game stores a set of hidden values representing primitive emotional "states" or "moods." The player is never explicitly shown these numbers; instead, they must decode their current state by observing symptoms in the world and the protagonist's behavior.

* **Dynamic Alteration:** These hidden emotional states are continuously altered by the player's dialogue choices and reactions to game events.
* **Gameplay Effects:** Due to the protagonist's extreme emotional instability, these states heavily influence multiple game systems:
  * **Visuals and Perception:** Emotional states dictate the graphical style of the game via shaders, HSL shifts, texture changes, and environmental shifts. Extreme states trigger hallucinations known as **"Echoes."**
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

## Story

## World

## Technical specification (if applicable)

## Team
1. Matteo Bellino
2. Franco Antonini
3. Daniel Lazzarotto
4. Alba Suli
5. Gaia Vizza
