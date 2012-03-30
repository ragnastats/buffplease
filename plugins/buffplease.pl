package Buff;

# Perl includes
use strict;

# Kore includes
use Settings;
use Plugins;
use Network;
use Globals;
use Data::Dumper;

our $buff ||= {
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

							
Plugins::register("Buff Please?", "Version 0.1 r5", \&unload);
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
	my $time = Time::HiRes::time();

	if(scalar keys %{$buff->{queue}})
	{	
		while(my($userName, $queue) = each(%{$buff->{queue}}))
		{	
			# If the request is older than 30 seconds... delete
			if($buff->{$userName}->{time} < $time - 30) {
				delete($buff->{queue}->{$userName});
			}
			else
			{
				if($buff->{$userName}->{please} > $time - 30) {
					my $command = shift(@{$buff->{queue}->{$userName}});					
					push(@{$buff->{commands}}, $command);
				}
				
				elsif($buff->{$userName}->{plz} > $time - 30) {
					$buff->{$userName}->{plzTimeout} = $time + 15;
					delete($buff->{$userName}->{plz});
					
					my $randomPhrase = $buff->{wit}->[rand @{$buff->{wit}}];
					Commands::run("c $randomPhrase");
				}
				
				unless(@{$buff->{queue}->{$userName}}) {
					delete($buff->{queue}->{$userName});
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
				
				$buff->{lastSkill} = {'timeout'	=> $time,
									  'skill'	=> $command->{skill}};
									  
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
			
			unless($buff->{ignore}->{$skill->getName()})
			{
				$buff->{messages}->{$skillID} = $skill->getName();
				
				if($buff->{aliases}->{$skill->getName()}) {
					$buff->{messages}->{$skillID} .= "|".$buff->{aliases}->{$skill->getName()};
				}
			}
		}	
	}
}

sub parseSkill
{
	my($hook, $args) = @_;
	my $time = Time::HiRes::time();
	
	# Am I casting?
	if($args->{sourceID} == $accountID)
	{
		if($hook eq 'packet/skill_cast')
		{			
			$buff->{time} = $time + (($args->{wait}) / 1000);
		}
		elsif($hook eq 'packet/skill_used_no_damage')
		{
			my $actor = Actor::get($args->{targetID});
			
		
			if($args->{skillID} == 28)
			{
				$buff->{$actor->{name}}->{lastHeal} = $time;
			
				if($buff->{$actor->{name}}->{healFor} > 0)
				{
					$buff->{$actor->{name}}->{healFor} -= $args->{amount};
					
					# If we're still below the heal amount...
					if($buff->{$actor->{name}}->{healFor} > 0) {
						
						$buff->{$actor->{name}}->{please} = $time;
						$buff->{$actor->{name}}->{time} = $time;
					
						if($actor->{name} eq $char->{name}) {
							unshift(@{$buff->{queue}->{$actor->{name}}}, {'type' => 'ss', 'skill' => 28, 'user' => $actor->{name}});
						}
						else {			
							unshift(@{$buff->{queue}->{$actor->{name}}}, {'type' => 'sp', 'skill' => 28, 'user' => $actor->{name}});
						}
					}
				}
			}

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
				$buff->{time} = $time + (($args->{tick}) / 1000);
			}
		}
	}
}

sub parseChat
{
	my($hook, $args) = @_;
	my $time = Time::HiRes::time();

	
	if($hook eq 'packet_selfChat')
	{
		$args->{Msg} = $args->{msg};
		$args->{MsgUser} = $args->{user};
	}
	
	if($args->{Msg} =~ /p+(l|w)+e+a+s+(e+)?|p+w+e+s+e/i)
	{
		$buff->{$args->{MsgUser}}->{please} = $time;
	}
	
	if($args->{Msg} =~ /\b(p+l+z+|p+l+s+)\b/i)
	{
		# Unless this person has already been corrected.
		unless($buff->{$args->{MsgUser}}->{plzTimeout} > $time) {
			$buff->{$args->{MsgUser}}->{plz} = $time;
		}
	}
	
	if($args->{Msg} =~ /([0-9,]+)(k)?/i)
	{
		my $hp = $1;
		my $modifier = $2;

		$hp =~ s/,//;
		
		if($modifier) {
			$hp *= 1000
		}
	
		if($hp > 20000) {
			$hp = 20000;
		}
		
		$buff->{$args->{MsgUser}}->{healFor} = $hp;
	}

	if($args->{Msg} =~ /more/i)
	{
		# If this user has already been healed in the past 10 seconds
		if($buff->{$args->{MsgUser}}->{lastHeal} + 10 > $time)
		{
			$buff->{$args->{MsgUser}}->{please} = $time;
			$buff->{$args->{MsgUser}}->{time} = $time;
		
			if($args->{MsgUser} eq $char->{name}) {
				unshift(@{$buff->{queue}->{$args->{MsgUser}}}, {'type' => 'ss', 'skill' => 28, 'user' => $args->{MsgUser}});
			}
			else {			
				unshift(@{$buff->{queue}->{$args->{MsgUser}}}, {'type' => 'sp', 'skill' => 28, 'user' => $args->{MsgUser}});
			}			
		
			if($buff->{$args->{MsgUser}}->{healFor} < 5000) {
				$buff->{$args->{MsgUser}}->{healFor} = 5000;
			}
		}
	}
	
	while(my($skillID, $message) = each(%{$buff->{messages}}))
	{
		if($args->{Msg} =~ /$message/i) {
			$buff->{$args->{MsgUser}}->{time} = $time;
				
			if($args->{MsgUser} eq $char->{name}) {
				unshift(@{$buff->{queue}->{$args->{MsgUser}}}, {'type' => 'ss', 'skill' => $skillID, 'user' => $args->{MsgUser}});
			}
			else {			
				unshift(@{$buff->{queue}->{$args->{MsgUser}}}, {'type' => 'sp', 'skill' => $skillID, 'user' => $args->{MsgUser}});
			}
		}
	}
	
	if($args->{Msg} =~ /debug/i)
	{
		print(Dumper($buff->{messages}));
#		print(Dumper($char));
	}
}

1;