package Buff;

# Perl includes
use strict;
use Data::Dumper;
use Storable;

# Kore includes
use Settings;
use Plugins;
use Network;
use Globals;
use Match;

our $buff ||= {
				# This value is used to determine who will be buffed
				# 'all' buffs anyone who asks
				# 'guild' only buffs people in the following list of guilds
				'permission' => 'all',
				'guilds' => ['RagnaStats', 'RagnaStats.com'],
				
				# Use this to map what skills are triggered by the chat
				'aliases' 	=> {
								'Blessing'			=> '(all|full) buff|bless|buff',
								'Increase AGI'		=> '(all|full) buff|\bagi\b|buff',
								'Sanctuary'			=> 'sanc',
								'High Heal'			=> 'high|highness|\bhh\b',
								'Ruwach'			=> 'sight',
								'Impositio Manus'	=> '(all|full) buff|impo',
								'Kyrie Eleison'		=> '\bKE\b|Kyrie|\bKy\b',
								'Resurrection'		=> 'res\b|resu',
								'Status Recovery'	=> '(all|full) buff|status|recovery',
								'Assumptio'			=> '(all|full) buff|assu|buff',
								'Safety Wall'		=> 'wall',
								'Magnificat'		=> '\bmag\b|magni',
								'Secrament'			=> '(all|full) buff|secra|sacra|sacrement',
								'Cantocandidus'		=> 'canto',
								'Clementia'			=> 'clem',
								'Praefatio' 		=> 'prae', 
								'Renovatio'			=> '(all|full) buff|reno\b',
								'Full Chemical Protection' => 'fcp',
								'Endow Blaze'		=> '(flame|fire) endow|endow (fire|flame)',
								'Endow Tsunami'		=> '(ice|water) endow|endow (ice|water)',
								'Endow Tornado'		=> 'wind endow|endow wind',
								'Endow Quake'		=> '(earth|ground) endow|endow (earth|ground)'
								},
				
				# These skills will never be used
				'ignore'	=>	{
								'Teleport'		=> 1,
								'Warp Portal'	=> 1,
								},
								
				# Messages to make fun of people who say plz
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
				
our $commandUser ||= {};
our $commandQueue ||= {};
							
Plugins::register("Buff Please?", "Buff people when they ask", \&unload);
my $hooks = Plugins::addHooks(['mainLoop_post', \&loop],
								['packet/skills_list', \&parseSkills],
								['packet/skill_cast', \&parseSkill],
								['packet/skill_used_no_damage', \&parseSkill],
								['packet/actor_status_active', \&parseStatus],
								
								["packet_pubMsg", \&parseChat],
								["packet_partyMsg", \&parseChat],
								["packet_guildMsg", \&parseChat],
								["packet_selfChat", \&parseChat],
								["packet_privMsg", \&parseChat],
								
								['packet/actor_exists', \&parseActor],
								['packet/actor_info', \&parseInfo]);

								
sub unload
{
	Plugins::delHooks($hooks);
}

sub in_array {
    my ($arr,$search_for) = @_;
    foreach my $value (@$arr) {
        return 1 if $value eq $search_for;
    }
    return 0;
}

sub loop
{
	# This is where we periodically loop through the requested commands.
	my $time = Time::HiRes::time();

	if(scalar keys %{$commandQueue})
	{	
		while(my($userName, $queue) = each(%{$commandQueue}))
		{		
			# If the request is older than 30 seconds... delete
			if($commandUser->{$userName}->{time} < $time - 30) {
				delete($commandQueue->{$userName});
			}
			else
			{
				# Have they said please within 30 seconds?
				if($commandUser->{$userName}->{please} > $time - 30) {
					my $command = shift(@{$commandQueue->{$userName}});					
					push(@{$buff->{commands}}, $command);
				}
				
				# Have they said plz within 30 seconds?
				elsif($commandUser->{$userName}->{plz} > $time - 30) {
					# Set the timeout to 7 seconds from now
					$commandUser->{$userName}->{plzTimeout} = $time + 7;
					delete($commandUser->{$userName}->{plz});
					
					my $randomPhrase = $buff->{wit}->[rand @{$buff->{wit}}];
					Commands::run("c $randomPhrase");
				}
				
				# If the user queue is empty, we don't need to store an empty value.
				unless(@{$commandQueue->{$userName}}) {
					delete($commandQueue->{$userName});
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
				my $player_name = $command->{user};
				$player_name =~ s/\\([^\\])/$1/g;

                my $player = Match::player($player_name, 1);

				# Remember this skill as the last skill we casted
				$buff->{lastSkill} = {'timeout'	=> $time,
									  'skill'	=> $command->{skill}};
				
				if($buff->{permission} eq 'guild')
				{
					unless(in_array($buff->{guilds}, $player->{guild}->{name}))
					{
						next;
					}
				}

                # Ensure the player still exists before casting
                if($player)
                {
                    # Sanitize usernames by adding slashes
                    my $sanitized = $player_name;
                    $sanitized =~ s/'/\\'/g;
                    $sanitized =~ s/;/\\;/g;
                    Commands::run("$command->{type} $command->{skill} '$sanitized'");
                }
                else
                {
                    $buff->{lastSkill}->{timeout} = $time - 5;
                }
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

			$buff->{skillsAvailable}->{$skillID} = {
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
				$commandUser->{$actor->{name}}->{lastHeal} = $time;
			
				# If the player requested to be healed for a specific amount (heal 10k please)
				if($commandUser->{$actor->{name}}->{healFor} > 0)
				{
					$commandUser->{$actor->{name}}->{healFor} -= $args->{amount};
					
					# If they still need more heals...
					if($commandUser->{$actor->{name}}->{healFor} > 0) {
						
						$commandUser->{$actor->{name}}->{please} = $time;
						$commandUser->{$actor->{name}}->{time} = $time;
	
						# Add heal to the queue again
						if($actor->{name} eq $char->{name}) {
							unshift(@{$commandQueue->{$actor->{name}}}, {'type' => 'ss', 'skill' => 28, 'user' => $actor->{name}});
						}
						else {			
							unshift(@{$commandQueue->{$actor->{name}}}, {'type' => 'sp', 'skill' => 28, 'user' => $actor->{name}});
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
	my $chat = Storable::dclone($args);
	
	# selfChat returns slightly different arguements, let's fix that
	if($hook eq 'packet_selfChat')
	{
		$chat->{Msg} = $chat->{msg};
		$chat->{MsgUser} = $chat->{user};
	}
	
	# Sanitize potential regex in player names and messages.
	$chat->{MsgUser} =~ s/[-\\.,_*+?^\$\[\](){}!=|]/\\$&/g;
	$chat->{Msg} =~ s/[-\\.,_*+?^\$\[\](){}!=|]/\\$&/g;

	# Loop through the list of available skills
	while(my($skillID, $skillName) = each(%{$buff->{skills}}))
	{
		# Remove whitespace from skill names, Gravity is not to be trusted!
		$skillName =~ s/^\s+//;
		$skillName =~ s/\s+$//;
	
		# If the skill name occurs in this user's message
		if($chat->{Msg} =~ /$skillName/i) {
			# Match the string following a skill name			
			$chat->{Msg} =~ m/(?:$skillName)(?:\w+)?(?:\s+)?([^\s"']+|".+"|'.+')/i;
		
			# Save it and strip quotes
			my $potentialPlayer = $1;
			$potentialPlayer =~ s/["']//g;
            
			# Make sure it's defined and not please
			if($potentialPlayer and $potentialPlayer !~ /p+(l|w)+e+a+s+(e+)?|p+w+e+s+e/i)
			{
				my $player = Match::player($potentialPlayer, 1);
				my $playerName = '';
				
				# Is it a player?
				if($player) {
					$playerName = $player->{name};
				}
								
				# Is it me?
				elsif($char->{name} =~ /^$potentialPlayer/i) {
					$playerName = $char->{name};
				}
				
				# Cast on the requested player
				
				if($playerName) {
					$chat->{MsgUser} = $playerName;
				}
			}
			
			$commandUser->{$chat->{MsgUser}}->{time} = $time;
			
			# If you're the one asking for something, you need to use skill self (ss)
			if($chat->{MsgUser} eq $char->{name}) {
				unshift(@{$commandQueue->{$chat->{MsgUser}}}, {'type' => 'ss', 'skill' => $skillID, 'user' => $chat->{MsgUser}});
			}
			
			# Otherwise use skill on a player (sp)
			else {
				unshift(@{$commandQueue->{$chat->{MsgUser}}}, {'type' => 'sp', 'skill' => $skillID, 'user' => $chat->{MsgUser}});
			}
		}
	}

	# Please?
	if($chat->{Msg} =~ /p+(l|w)+e+a+s+(e+)?|p+w+e+s+e/i)
	{
		$commandUser->{$chat->{MsgUser}}->{please} = $time;
	}
	
	# Plz?
	if($chat->{Msg} =~ /\b(p+l+z+|p+l+s+|p+l+o+x+)\b/i)
	{
		# Unless this person has already been corrected.
		if($commandUser->{$chat->{MsgUser}}->{plzTimeout} < $time) {
			$commandUser->{$chat->{MsgUser}}->{plz} = $time;
		}
	}

	# Heal 10k, 4000, etc.
	if($chat->{Msg} =~ /([0-9,]+)\s*([kx]\s)?/i)
	{
		my $hp = $1;
		my $modifier = $2;

		$hp =~ s/,//;
		
		if($modifier) {
			$hp *= 1000
		}
	
		# Most people don't have more than 30,000 HP
		if($hp > 30000) {
			$hp = 30000;
		}
		
		$commandUser->{$chat->{MsgUser}}->{healFor} = $hp;
	}

	# HEAL ME MORE!!!
	if($chat->{Msg} =~ /more/i)
	{
		# If this user has already been healed in the past 10 seconds
		if($commandUser->{$chat->{MsgUser}}->{lastHeal} + 10 > $time)
		{
			$commandUser->{$chat->{MsgUser}}->{please} = $time;
			$commandUser->{$chat->{MsgUser}}->{time} = $time;
		
			if($chat->{MsgUser} eq $char->{name}) {
				unshift(@{$commandQueue->{$chat->{MsgUser}}}, {'type' => 'ss', 'skill' => 28, 'user' => $chat->{MsgUser}});
			}
			else {			
				unshift(@{$commandQueue->{$chat->{MsgUser}}}, {'type' => 'sp', 'skill' => 28, 'user' => $chat->{MsgUser}});
			}			
		
			# Someone asking for more probably wants a couple heals
			if($commandUser->{$chat->{MsgUser}}->{healFor} < 5000) {
				$commandUser->{$chat->{MsgUser}}->{healFor} = 5000;
			}
		}
	}
	
	if($chat->{Msg} =~ /debug/i)
	{
#		print(Dumper($buff->{skillsAvailable}));
		print(Dumper($commandQueue));
		print(Dumper($commandUser));
		print(Dumper($buff));
#		print(Dumper($char));
	}
}

sub parseActor
{
	my($hook, $args) = @_;
	my $playerID = unpack('V', $args->{ID});
	my $guildID = unpack('V', $args->{guildID});
	my $time = Time::HiRes::time();
	
	$buff->{player}->{$playerID} = $guildID;
	
	unless($buff->{guild}->{$guildID})
	{
		$messageSender->sendGetPlayerInfo($args->{ID});
	}
}

sub parseInfo
{
	my($hook, $args) = @_;
	
	if($args->{guildName})
	{
		my $playerID = unpack('V', $args->{ID});
		my $guildID = $buff->{player}->{$playerID};

		$buff->{guild}->{$guildID} = $args->{guildName};		
	}
}

1;
