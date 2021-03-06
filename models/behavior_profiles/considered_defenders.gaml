/**
* Name: Considered Defenders behavior profile

* Author: Pierre Blarre
* 
* Description:   
* 
* Can-do defenders : 
* - are strongly committed to stay and defend their house
* - are aware of the risks and made deliberate efforts to prepare and train
* 
*  They can :
*  - Increase terrain and buildings resitance
*  - Fight fire, although not as well as firefighters
* 
*/

model Bushfires_BDI_Cognitive_Biases

import "../main.gaml"

species considered_defenders parent: resident
{
	init
	{
		probability_to_react <- 90.0; //Highest probability to react
		default_probability_to_react <- 90.0;
		
		//Default beliefs
		do add_belief(no_danger_belief,30.0);
		do add_belief(can_defend_belief,probability_to_react);
		
		escape_target <- home; //They want to defend their house
		speed <- rnd(18.0, 25.0) # km / # h; // If you want them faster so they die less use : rnd(30.0, 50.0) 
		//Highly motivated, high risk awareness, high knowledge
		motivation <- max([0, rnd(3, 5) + motivation]);
		risk_awareness <- max([0, rnd(3, 5) + risk_awareness]);
		knowledge <- max([0, rnd(4, 5) + knowledge]);
		
	}
	
	//they have similar strengh in escaping and defineding
	rule belief: immediate_danger_belief new_desire: escape_desire strength: 40.0 remove_desire: work_desire and home_desire;
	rule belief: can_defend_belief new_desire: defend_desire strength: 40.0;
	
}

