package Buff;

# Perl includes
use strict;

# Kore includes
use Settings;
use Plugins;
use Network;
use Globals;
use Data::Dumper;

our $buff = {
				'aliases' 	=> {
								'Blessing'			=> 'bless|buff',
								'Increase AGI'		=> '\bagi\b|buff',
								'Sanctuary'			=> 'sanc',
								'High Heal'			=> 'high|highness|\bhh\b',
								'Ruwach'			=> 'sight',
								'Impositio Manus'	=> 'impo',
								'Kyrie Eleison'		=> 'KE|Kyrie',
								'Resurrection'		=> 'res',
								'Assumptio'			=> 'assu|buff',
								'Safety Wall'		=> 'wall',
								'Magnificat'		=> '\bmag\b',
								},
							
				'ignore'	=>	{
								'Teleport'		=> 1,
								'Warp Portal'	=> 1,
								'Epiclesis'		=> 1,
								'Kyrie Eleison'	=> 1,
								'Holy Light'	=> 1,
								},
								
				'wit'		=> [
								"You mean please?",
								"Don't you mean please?",
								"You meant to say 'please', right?",
								"Please check your dictionary.",
								"Say please~",
								"Plz doesn't cut it.",
								"Pls isn't very polite.",
								"Just say please :3",
								"Please works better.",
								"lrn2spell",
								"P-l-e-a-s-e",
								"Just say please?",
								"This would be a lot easier if you said 'please'.",
								"Saying please goes a long way.",
								"Some day you'll learn... (to say please)",
								"Have you tried saying please?",
								"Where are your manners? Please try again.",
								"Say please first~",
								"Please please please!",
								"What's so hard about saying please?",
								]
				};

our $userData ||= {};
our $userQueue ||= {};
							
Plugins::register("Buff Please?", "Version 0.1 r7", \&unload);
my $hooks = Plugins::addHooks(['mainLoop_post', \&loop],
								['packet/skills_list', \&parseSkills],
								['packet/skill_cast', \&parseSkill],
								['packet/skill_used_no_damage', \&parseSkill],
								['packet/actor_status_active', \&parseStatus],
								
								["packet_pubMsg", \&parseChat],
								["packet_partyMsg", \&parseChat],
								["packet_guildMsg", \&parseChat],
								["packet_selfChat", \&parseChat],
								["packet_privMsg", \&parseChat]);

								
sub unload
{
	Plugins::delHooks($hooks);
}

sub loop
{
	# This is where we periodically loop through the requested commands.
	my $time = Time::HiRes::time();

	if(scalar keys %{$userQueue})
	{	
		while(my($userName, $queue) = each(%{$userQueue}))
		{	
			# If the request is older than 30 seconds... delete
			if($userData->{$userName}->{time} < $time - 30) {
				delete($userQueue->{$userName});
			}
			else
			{
				# Have they said please within 30 seconds?
				if($userData->{$userName}->{please} > $time - 30) {
					my $command = shift(@{$userQueue->{$userName}});					
					push(@{$buff->{commands}}, $command);
				}
				
				# Have they said plz within 30 seconds?
				elsif($userData->{$userName}->{plz} > $time - 30) {
					$userData->{$userName}->{plzTimeout} = $time + 15;
					delete($userData->{$userName}->{plz});
					
					my $randomPhrase = $buff->{wit}->[rand @{$buff->{wit}}];
					Commands::run("c $randomPhrase");
				}
				
				# If the user queue is empty, we don't need to store an empty value.
				unless(@{$userQueue->{$userName}}) {
					delete($userQueue->{$userName});
				}
			}
		}
	}
		
	if($buff->{commands} and @{$buff->{commands}} and $buff->{time} < $time)
	{		
		# Check every 0.1 seconds
		$buff->{time} = $time + 0.1;
	
		# It took 5 seconds to cast a skill? It might have gotten interrupted.
		if($buff->{lastSkill}->{timeout} + 5 < $time)
		{
			unless($char->statusesString =~ /EFST_POSTDELAY/)
			{
				my $command = shift(@{$buff->{commands}});
				
				# Remember this skill as the last skill we casted
				$buff->{lastSkill} = {'timeout'	=> $time,
									  'skill'	=> $command->{skill}};
				
				# Sanitize usernames by adding slashes
				$command->{user} =~ s/'/\\'/g;
				Commands::run("$command->{type} $command->{skill} '$command->{user}'");
			}
		}
	}
}

sub parseSkills
{
	# Got a skills list?
	for my $handle (@skillsID)
	{
		# Code repurposed from the openkore source
		my $skill = new Skill(handle => $handle);

		if($char->{skills}{$handle}{lv})
		{
			my $skillID = $char->{skills}{$handle}{ID};

			$buff->{skills}->{$skillID} = {
											'name'	=> $skill->getName(),
											'level'	=> $char->getSkillLevel($skill),
											'range'	=> $char->{skills}{$handle}{range},
											'sp'	=> $char->{skills}{$handle}{sp}
										};
			
			# Don't add ignored skills to the skills list!
			unless($buff->{ignore}->{$skill->getName()})
			{
				$buff->{skills}->{$skillID} = $skill->getName();
				
				# Append aditional aliases if this skill has any
				if($buff->{aliases}->{$skill->getName()}) {
					$buff->{skills}->{$skillID} .= "|".$buff->{aliases}->{$skill->getName()};
				}
			}
		}
	}	
}

sub parseSkill
{
	my($hook, $args) = @_;
	my $time = Time::HiRes::time();
	
	# Am I the one casting?
	if($args->{sourceID} == $accountID)
	{
		if($hook eq 'packet/skill_cast')
		{
			# Get the skill delay and wait that long before trying to do anything else
			$buff->{time} = $time + (($args->{wait}) / 1000);
		}
		elsif($hook eq 'packet/skill_used_no_damage')
		{
			my $actor = Actor::get($args->{targetID});
			
			# Skill 28 is heal
			if($args->{skillID} == 28)
			{
				$buff->{$actor->{name}}->{lastHeal} = $time;
			
				# If the player requested to be healed for a specific amount (heal 10k please)
				if($buff->{$actor->{name}}->{healFor} > 0)
				{
					$buff->{$actor->{name}}->{healFor} -= $args->{amount};
					
					# If they still need more heals...
					if($buff->{$actor->{name}}->{healFor} > 0) {
						
						$buff->{$actor->{name}}->{please} = $time;
						$buff->{$actor->{name}}->{time} = $time;
	
						# Add heal to the queue again
						if($actor->{name} eq $char->{name}) {
							unshift(@{$userQueue->{$actor->{name}}}, {'type' => 'ss', 'skill' => 28, 'user' => $actor->{name}});
						}
						else {			
							unshift(@{$userQueue->{$actor->{name}}}, {'type' => 'sp', 'skill' => 28, 'user' => $actor->{name}});
						}
					}
				}
			}

			# Skill casting complete, we don't need to remember the last skill anymore
			if($args->{skillID} == $buff->{lastSkill}->{skill}) {		
				delete($buff->{lastSkill});
			}
		}
	}
}

sub parseStatus
{
	my($hook, $args) = @_;
	my $time = Time::HiRes::time();

	# Is this my status?
	if($args->{ID} == $accountID)
	{	
		# Status type is: EFST_POSTDELAY
		if($args->{type} == 46)
		{
			if($args->{tick})
			{
				# Get the skill cooldown and wait that long before trying to do anything else
				$buff->{time} = $time + (($args->{tick}) / 1000);
			}
		}
	}
}

sub parseChat
{
	my($hook, $args) = @_;
	my $time = Time::HiRes::time();

	# selfChat returns slightly different arguements, let's fix that
	if($hook eq 'packet_selfChat')
	{
		$args->{Msg} = $args->{msg};
		$args->{MsgUser} = $args->{user};
	}
	
	# Please?
	if($args->{Msg} =~ /p+(l|w)+e+a+s+(e+)?|p+w+e+s+e/i)
	{
		$userData->{$args->{MsgUser}}->{please} = $time;
	}
	
	# Plz?
	if($args->{Msg} =~ /\b(p+l+z+|p+l+s+|p+l+o+x+)\b/i)
	{
		# Unless this person has already been corrected.
		if($userData->{$args->{MsgUser}}->{plzTimeout} < $time) {
			$userData->{$args->{MsgUser}}->{plz} = $time;
		}
	}
	
	# Heal 10k, 4000, etc.
	if($args->{Msg} =~ /([0-9,]+)(k)?/i)
	{
		my $hp = $1;
		my $modifier = $2;

		$hp =~ s/,//;
		
		if($modifier) {
			$hp *= 1000
		}
	
		# Most people don't have more than 20,000 HP
		if($hp > 20000) {
			$hp = 20000;
		}
		
		$userData->{$args->{MsgUser}}->{healFor} = $hp;
	}

	# HEAL ME MORE!!!
	if($args->{Msg} =~ /more/i)
	{
		# If this user has already been healed in the past 10 seconds
		if($userData->{$args->{MsgUser}}->{lastHeal} + 10 > $time)
		{
			$userData->{$args->{MsgUser}}->{please} = $time;
			$userData->{$args->{MsgUser}}->{time} = $time;
		
			if($args->{MsgUser} eq $char->{name}) {
				unshift(@{$userQueue->{$args->{MsgUser}}}, {'type' => 'ss', 'skill' => 28, 'user' => $args->{MsgUser}});
			}
			else {			
				unshift(@{$userQueue->{$args->{MsgUser}}}, {'type' => 'sp', 'skill' => 28, 'user' => $args->{MsgUser}});
			}			
		
			# Someone asking for more probably wants a couple heals
			if($userData->{$args->{MsgUser}}->{healFor} < 5000) {
				$userData->{$args->{MsgUser}}->{healFor} = 5000;
			}
		}
	}
	
	# Loop through the list of available skills
	while(my($skillID, $skillName) = each(%{$buff->{skills}}))
	{
		# If the skill name occurs in this user's message
		if($args->{Msg} =~ /$skillName/i) {
			$userData->{$args->{MsgUser}}->{time} = $time;
			
			# If you're the one asking for something, you need to use skill self (ss)
			if($args->{MsgUser} eq $char->{name}) {
				unshift(@{$userQueue->{$args->{MsgUser}}}, {'type' => 'ss', 'skill' => $skillID, 'user' => $args->{MsgUser}});
			}
			
			# Otherwise use skill on a player (sp)
			else {
				unshift(@{$userQueue->{$args->{MsgUser}}}, {'type' => 'sp', 'skill' => $skillID, 'user' => $args->{MsgUser}});
			}
		}
	}
	
	if($args->{Msg} =~ /debug/i)
	{
		print(Dumper($buff->{skills}));
#		print(Dumper($char));
	}
}

1;