/**
* Name:  People specie
*
* Author: Pierre Blarre
* 
* Authors of the Cognitive Biases algorithms  : Maël Arnaud, Carole Adam, Julie Dugdale
* Scientific article : The role of cognitive biases in reactions to bushfires
* 
* Based on a model without BDI architecture by : Sofiane Sillali, Thomas Artigue, Pierre Blarre
* 
* Description: 
* Mother specie for residents, firefighters and policemen. 
* Common moving skills (go to work, go home, go to shelter) following the road network
* Actions regarding dangerous situations (eaction to danger)
* Communication ( Send and receive messages )
* 
*/

model Bushfires_BDI_Cognitive_Biases
import "main.gaml"

species people skills: [moving, fipa] control: simple_bdi
{
	// Physical attributes
	int id <- 1;
	float energy <- float(rnd(200, 255));
	bool alive <- true;
	point target;
	rgb color <- # green;
	building home;
	building work;
	bool at_home;
	bool at_work <- false;
	bool in_safe_place <- false;
	bool warning_sent <- false;
	bool end_message_sent <- false;
	agent escape_target <- nil;
	bool on_alert <- false;
	bool fighting_fire <- false;
	bool go_fighting <- false;
	
	// Psychological attributes
	int motivation; //higher motivation increases speed and defense capacity
	int risk_awareness; //higher awareness will increase response to messages and escape_intention
	int knowledge; //level of knowledge crisis management and technical abilities -> should influend cognitive biases
	int training; //level of training will influence the three previous values
	int fear_of_fire <- rnd(0, 1); //will influence decision making	
	
	float default_probability_to_react <- 60.0; //by default we suppose at least 60% of people will react to an alert
	float probability_to_react <- 60.0; //by default we suppose at least 60% of people will react to an alert
	int nb_of_warning_msg <- 0; //total warning messages
	int nb_of_ignored_warning_msg <- 0;
	
	int nb_of_stop_msg <- 0; //total finished alert messages
	int nb_of_ignored_stop_msg <- 0;
	int nb_of_ignored_stop_msg_cb <- 0;
	
	//Definition of the variables featured in the BDI architecture. 
	//How is this used, I am not sure. TODO: research how this should be used
	float plan_persistence <- 1.0; 
	float intention_persistence <- 1.0;
	bool probabilistic_choice <- false;
	
	//Cognitive Biases
	//Whether the agent's choices will be influenced or not by the cognitive biases algorithms
	bool cognitive_biases_influence <- false;
	bool neglect_of_probability_cb_influence <- false;
	bool semmelweis_reflex_cb_influence <- false;
	bool illusory_truth_effect_cb_influence <- false;
	
    //Beliefs
	float default_belief_strengh <- 0.5;
	predicate no_danger_belief <- new_predicate("no_danger_belief",true);
	predicate potential_danger_belief <- new_predicate("potential_danger_belief",true);
	predicate immediate_danger_belief <- new_predicate("immediate_danger_belief",true);
	predicate risk_of_fires_today <- new_predicate("risk_of_fire",true);
	predicate can_defend_belief <- new_predicate("can_defend_belief",true);
	predicate i_can_escape <- new_predicate("i_can_escape",true); 
	
	//Desires
	predicate work_desire <- new_predicate("work_desire",10);
	predicate home_desire <- new_predicate("home_desire",20);
	predicate call_911_desire <- new_predicate("call_911_desire",30);
	predicate defend_desire <- new_predicate("defend_desire",40);
	predicate escape_desire <- new_predicate("escape_desire",50); //desire to escape is the equal to the desire to shelter
	
	//Avoid running perceptions more than once
	//The problem is, when there's fire detection, the agents perceives more than one burning plot
	//The result is that he's going to go through the same choice more than once for the same fire
	//So we will store when perception occured to avoid duplication
	//TODO: is it right? Shouldn't we consider than the more burning plots he sees the more strengh his beliefs should have (or change anyway)?
	bool has_perceived_smoke <- false;
	bool has_perceived_fire <- false;
		
	// OLD BDI - Left for now for firefighters and policemen compatibility TODO convert them to simple_bdi architecture
	list<string> desires <- nil;
	string intention <- nil;
	string belief <- "no_danger_belief";
	// OLD BDI Intentions
	string run_away <- "Escape";
	string defend <- "Defend";
	string protect <- "Protect";
	string ask_for_help <- "I need help";
	// OLD BDI Beliefs
	string no_danger <- "No danger";
	string potential_danger <- "Potential danger";
	string immediate_danger <- "Immediate danger";

	//Simulation tools
	int last_cycle_update <- 0; //use to avoid duplicating action within same cycle

	init
	{
		ids <- ids + 1;
		id <- ids;

		// these attributes will vary for different behavior profiles
		training <- trained_population ? 2 : 0; // if training set to true it will influence psychological attributes
		risk_awareness <- training + fear_of_fire;
		motivation <- training - fear_of_fire;
		knowledge <- training - fear_of_fire;
		do add_belief(no_danger_belief, default_belief_strengh);
	}

	aspect sphere3D { draw sphere(3) at: { location.x, location.y, location.z + 3 } color: color; }
//	aspect sphere3D { draw circle(3) at: { location.x, location.y } color: color; } //2d version

	//change color when on alert
	action color { color <- on_alert ? rgb(int(energy), int(energy), 0) : rgb(0, int(energy), 0); }
	
	action status (string msg)
	{
		write ""+cycle+" "+string(self) + " ("+energy+") : " + msg;
		 
		if(show_residents_BDI)
		{
			write "B:" + length(belief_base) + ":" + belief_base; 
			write "D:" + length(desire_base) + ":" + desire_base; 
			write "I:" + length(intention_base) + ":" + intention_base; 
		}
	}
	
	// Go somewhere with the road network
	// @params : destination (agent)
	// @returns : boolean (reached destination or not)
	action go_to (agent a)
	{
		if (!(target overlaps a)) { target <- any_location_in(a); } // set target destination to agent location
		do goto target: target on: road_network; // move along roads TODO check if roads are usable if not, should try to walk
		if (location = target) { return true; } 
		else { return false; }
	}
	
	//for now unused, but should be used when roads are unusable
	action walk (agent a)
	{
		speed <- rnd(5.0, 10.0) # km / # h; //We assume they are at least going at average walking speed
		if (!(target overlaps a)) { target <- any_location_in(a); } // set target destination to agent location
		do goto target: target; // move anywhere
		if (location = target) { return true; } //reached 
		return false;
	}

	//Send message to other agents
	action send_msg (list<agent> main_recipients, list<agent> main_secondary, string msg)
	{
		if (empty(main_recipients)) // if main list empty, we use the second list
		{
			main_recipients <- main_secondary;
		}
		if (!empty(main_recipients))
		{
			do start_conversation(to: main_recipients, protocol: 'fipa-propose', performative: 'propose', contents: [msg]);
		}
	}

	//@returns agent
	action get_closest_safe_place
	{
		float dist_to_closest_bunker;
		float dist_to_closest_exit;
		building closest_bunker;
		city_exit closest_exit;
		
		if (nb_bunker > 0)
		{
			closest_bunker <- (building where (each.bunker) closest_to location);
			dist_to_closest_bunker <- closest_bunker distance_to location;
		}

		if (nb_exit > 0)
		{
			closest_exit <- city_exit closest_to location;
			dist_to_closest_exit <- closest_exit distance_to location;
		}

		if (dist_to_closest_bunker < dist_to_closest_exit and closest_bunker != nil)
		{
			return closest_bunker;
		} 
		else if (closest_exit != nil)
		{
			return closest_exit;
		}

		return agent(nil);
	}

	//Get info on close fire(s) - is there one and if yes from where?
	// returns : bool fire is close, bool fire_is_north, bool fire_is_west
	action get_closest_fire_at_hurting_distance
	{
		bool danger <- false;
		bool fire_is_north <- false;
		bool fire_is_west <- false;
		list<plot> plotS_in_fire <- plot at_distance field_of_view where each.burning; //get burning plots in view distance

		// S'il existe des feux à distance dangeureuse
		if (length(plotS_in_fire) > 0)
		{
			danger <- true;
			plot plot_in_fire <- plotS_in_fire closest_to location; //get the closest one from location
			if (plot_in_fire.location.x < location.x) { fire_is_west <- true; }
			if (plot_in_fire.location.y < location.y) { fire_is_north <- true; }
		}

		return [danger, fire_is_north, fire_is_west];
	}


	// Get the city exit to try avoid the fire
	// @params : information du feu, bool:trouver le plus proche, inclure les bunker
	// @returns : target point
	action get_city_exit_opposed_to_fire (list<bool> fire_direction, bool m_closest, bool include_bunker)
	{
		bool fire_is_north <- fire_direction[1];
		bool fire_is_west <- fire_direction[2];
		list<agent> exit_at_Y <- nil;
		list<agent> exit_at_X <- nil;
		list<agent> exits_found <- nil;
		point target_point <- nil;

		// Get exit coordinates
		// North exits at south from fire. West exits as East from fire. Etc.
		exit_at_Y <- fire_is_north ? city_exit where (each.location.y > location.y) : city_exit where (each.location.y < location.y);
		exit_at_X <- fire_is_west ? city_exit where (each.location.x > location.x) : city_exit where (each.location.x < location.x);
		if (include_bunker) //Only when bunker buildings are activated
		{
			exit_at_Y <- exit_at_Y + (fire_is_north ? building where (each.bunker and each.location.y > location.y) : building where (each.bunker and each.location.y < location.y));
			exit_at_X <- exit_at_X + (fire_is_west ? building where (each.bunker and each.location.x > location.x) : building where (each.bunker and each.location.x < location.x));
		}

		if (length(exit_at_Y) > 0)
		{
			if (length(exit_at_X) > 0)
			{
				exits_found <- exit_at_Y inter exit_at_X;
				if (length(exits_found) = 0) { exits_found <- exit_at_Y; }
			}
		} 
		else
		{
			if (length(exit_at_X) > 0) { exits_found <- exit_at_X; }
		}

		if (length(exits_found) > 0)
		{
			agent exit_f <- m_closest ? exits_found closest_to location : one_of(exits_found);
			target_point <- exit_f != nil ? any_point_in(exit_f) : nil;
		}

		return target_point;
	}

	//Simulate watering terrain and cutting vegetation to avoid fire spreading
	action increase_terrain_resistance (int increase_value)
	{
		building bd_location <- at_home ? home : (at_work ? work : nil);
		if (bd_location != nil)
		{
			// neighboring nature plots
			list<plot> nature_plots <- plot where (!each.is_road and each.heat > -5.0) overlapping bd_location;

			//increase resistance
			if (length(nature_plots) > 0)
			{
				// Treat burning plots first
				plot a_plot <- one_of(nature_plots where each.burning);
				if (a_plot = nil) { a_plot <- one_of(nature_plots); }

				// Dimish plot heat
				a_plot.heat <- a_plot.heat - increase_value / 2;
				if (a_plot.heat <= -5.0) { a_plot.color <- # magenta; }
			}
		}
	}

	//Simulate  watering building and cutting vegetation around it to avoid fire spreading
	action increase_building_resistance (int increase_value)
	{
		if (at_home) { home.resistance <- home.resistance + int(increase_value / 2); }
		if (at_work) { work.resistance <- work.resistance + int(increase_value / 2); }
	}
	
	//Apply cognitive biases to probability to react
	//returns true/false on reaction and true/false to tell if it was influenced by a cognitive bias
	action cognitive_biases(predicate beliefName, float perceivedProbability, string called_from <- "")
//	action cognitive_biases(string called_from <- "")
	{
		bool influence <- true;
		bool react <- true; //should be removed
		
		if(neglect_of_probability_cb_influence)
		{
			influence <- bool(neglect_of_probability(beliefName, perceivedProbability));
			
			if(influence) { 
				nb_cb_influences <- nb_cb_influences + 1;
				if(show_cognitive_biases_messages) { do status("My probability to react ("+probability_to_react+") was influenced by neglect_of_probability in "+called_from); }
			}
		}
		
		if(semmelweis_reflex_cb_influence)
		{
			influence <- bool(semmelweis_reflex(beliefName));
			if(!influence) { 
				nb_cb_influences <- nb_cb_influences + 1;
				if(show_cognitive_biases_messages) { do status("My probability to react ("+probability_to_react+") is influenced by the semmelweis_reflex in "+called_from); }
			}
		}
		
		if(illusory_truth_effect_cb_influence)
		{
			do illusory_truth_effect(potential_danger_belief, probability_to_react);
			if(show_cognitive_biases_messages) { do status("My probability to react ("+probability_to_react+") is influenced by illusory_truth_effect in "+called_from); }
			nb_cb_influences <- nb_cb_influences + 1;
			influence <- true;
		}
		
		return influence;
	}
	
	
	//Cognitive Bias : Neglect of probability
	//Will influence the agent's belief's strength
	action neglect_of_probability(predicate beliefName, float perceivedProbability)
	{
		//TODO Should i do that or not?? If yes should I add it to the end of the algorithm?
		//if(!has_belief(beliefName)) { do add_belief(beliefName, probability_to_react);}
		
		bool probabilityHasChanged <- false;
		
		if(has_belief(beliefName)) //check if 
		{
			cb_nob_occurences <- cb_nob_occurences + 1; //count occurences
			
			float ancientBeliefProbability <- get_belief(beliefName).strength ; //get ancient belief strength
			float newBeliefProbability <- (ancientBeliefProbability + perceivedProbability > 100) ? 100.0 : ancientBeliefProbability + perceivedProbability; //get new beliefStrengh (cannot go over 100)
			
			float increasedProbability <- newBeliefProbability; //just for readability
			float decreasedProbability <- ancientBeliefProbability - perceivedProbability;
			
			//1 - ignore what is unlikely to happen, even if it's happening
            //1 - if newBeliefProbability is small and consequences are not perceived to be dire and consequences are not perceived to be extremely favourable
			if( newBeliefProbability < small_probability and risk_awareness < risk_awareness_average and !has_belief(immediate_danger_belief) )
			{
				do remove_all_beliefs(beliefName); //stop believing
				probabilityHasChanged <- true;
			}
			//2 - not likely to happen, but I desire/dread it so I will react
			//2 - if beliefProbability is small and (consequences are perceived to be dire or consequences are perceived to be extremely favourable)
			else if( newBeliefProbability  < small_probability and (risk_awareness >= 3 or has_belief(immediate_danger_belief)) )
			{
				do remove_all_beliefs(beliefName);
				do add_belief(beliefName, increasedProbability); // increase the Belief Probability
				probabilityHasChanged <- true;
			}
			//3 - under-estimate a high and medium probability of something happening
			else if( newBeliefProbability  > medium_high_probability ) 
			{
				do remove_all_beliefs(beliefName);
				do add_belief(beliefName, decreasedProbability); // decrease Belief Probability
				probabilityHasChanged <- true;
			}
		}
		
		return probabilityHasChanged;
	}
	
	
	//Cognitive Bias : Semmelweis Reflex : Clinging to a belief
	//Will influence the agent's belief on no / potential / immediate danger : Should I keep my belief/certainty?
	action semmelweis_reflex(predicate beliefName)
	{
		cb_sr_occurences <- cb_sr_occurences +1;
		if( (!has_belief(beliefName) or get_belief(beliefName).strength = 0) and (nb_of_warning_msg <= 3 or (!has_perceived_smoke and !has_perceived_fire)) )
		{
			do remove_all_beliefs(beliefName);
			do add_belief(beliefName, 0.0); // is this correct ... ?
			return true;
		}
		else if ( get_belief(beliefName).strength > 0 or (nb_of_warning_msg > 3 or has_perceived_smoke or has_perceived_fire) ) //I started to believe, I should change my certainty
		{
			if(show_residents_messages) { do status("I'm stuck within the Semmelweis Reflex"); }
			do remove_all_beliefs(beliefName); // is this correct ... ?
//			do add_belief(beliefName, probability_to_react); // is this correct ... ?
			return false;
		}
	}
	
	//Cognitive Illusory Truth effect
	//Will re-inforce agent's belief
	// "Info" = no / potential / immediate danger
	// "nb of occurences" = received_warnings
	action illusory_truth_effect(predicate beliefName, float perceivedProbability)
	{
		cognitive_biases_influence_occurence <- cognitive_biases_influence_occurence + 1;
		cb_iot_occurences <- cb_iot_occurences + 1;
		
		if( ! has_belief(beliefName) )
		{
			do add_belief(beliefName, perceivedProbability);
			return false;
		}
		else //reinforce belief strength
		{
			float illusoryProbability <- perceivedProbability +  perceivedProbability * nb_of_warning_msg / 100;
			if(illusoryProbability > 100) { illusoryProbability <- 100.0; }
			do remove_all_beliefs(beliefName);
			do add_belief(beliefName, illusoryProbability);
			return true;
		}
		
	}

}


