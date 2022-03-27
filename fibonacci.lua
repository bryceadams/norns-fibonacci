-- fibonacci
-- 0.1 @obi
-- inspirations and source @tehn @markwheeler
--
-- HOME
-- K1 toggles loop mode
-- K2 pauses/plays
-- K3 resets number
--
-- SETTINGS
-- E1 change page
-- K2/K3 toggle settings
-- E2 change first setting
-- E3 change second setting
--
-- LOOP MODE
-- E2 loop start
-- E3 loop size

local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
engine.name = "MollyThePoly"

local hs = include('lib/halfsecond')

local MusicUtil = require "musicutil"

local options = {}
options.OUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF"}
options.SCALE_NAMES = {}

local running = true

local mode = 1
local mode_names = {"", "PATTERN","SOUND"}

local numbers = {0, 1, 1}
local numbers_built = false
local current_number = 3
local current_number_part = 1

local midi_devices
local midi_device
local midi_channel

local notes = {}
local active_notes = {}

local loop_mode_on = false
local playing_forward = true

local main_sel = 1
local main_names = {"bpm","mult","root","scale","octaves","zero behaviour", "play probability", "play duplicates"}
local main_params = {"clock_tempo","step_div","root_note","scale_mode", "octaves", "zero_behaviour", "probability", "play_duplicates"}
local NUM_MAIN_PARAMS = #main_params

local snd_sel = 1
local snd_names = {"random sound type", "generate", "wave shape", "cut","sub osc level", "amp", "pulse width", "glide", "freq mod lfo", "freq mod env"}
local snd_params = {"random_sound_type", "generate_preset", "osc_wave_shape", "lp_filter_cutoff","sub_osc_level", "amp", "pulse_width_mod", "glide", "freq_mod_lfo", "freq_mod_env"}
local NUM_SND_PARAMS = #snd_params

local notes_off_metro = metro.init()

local random_sound_types = {"lead", "pad", "percussion"}

function generate_synth_preset()
  local sound_type = random_sound_types[params:get("random_sound_type")]
  MollyThePoly.randomize_params(sound_type)
end

function build_scale()
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 48) -- always all notes as may need higher numbers
  local num_to_add = 48 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[48 - num_to_add])
  end
end

function all_notes_off()
  -- Audio engine out
  if params:get("out") == 1 then
    for _, a in pairs(active_notes) do
      engine.noteOff(a)
    end
  end

  if (params:get("out") == 2 or params:get("out") == 3) then
    for _, a in pairs(active_notes) do
      midi_device:note_off(a, nil, midi_channel)
    end
  end
  active_notes = {}
end

-- dynamic might be better but can't figure out yet
function build_numbers()
    repeat
        local new_number = numbers[#numbers - 1] + numbers[#numbers]
        table.insert(numbers, new_number)
    until(string.len(new_number) >= 18)

    numbers_built = true
end

function step()
  while true do
    -- step div and @todo remove optional randomness?
    local step_div = params:get("step_div")
    if params:get('random_step_lengths') == 2 then
      -- use the golden ratio to determine if different length or not
      if math.random(1, 100) / 100 > 1/1.618 then
        step_div = math.random(1, 4)
      end
    end
    clock.sync(1/step_div)

    if running and numbers_built then
        -- PLAYING FORWARD
        if playing_forward then
          -- check end of number and tick if need to
          if current_number_part >= string.len(numbers[current_number]) then
              current_number = current_number + 1
              current_number_part = 1
          else
              current_number_part = current_number_part + 1
          end

          -- end of the line? reset
          local end_of_the_line = #numbers
          if loop_mode_on and params:get('loop_size') then
            end_of_the_line = params:get('loop_start') + params:get('loop_size')
          end
          
          if current_number > end_of_the_line then
            -- only for loop mode
             if loop_mode_on and params:get('loop_end') == 2 then
              -- set to play backwards and change current number
               playing_forward = false
               current_number = current_number - 1
               current_number_part = string.len(numbers[current_number]) - 1
             else
              reset()
             end
          end
        -- PLAYING IN REVERSE
        else
          -- check end of number and tick if need to
          if current_number_part == 1 then
              current_number = current_number - 1
              current_number_part = string.len(numbers[current_number])
          else
              current_number_part = current_number_part - 1
          end

          -- start of the line? reset (@todo reverse mode?)
          local start_of_the_line = 1
          if loop_mode_on and params:get('loop_size') then
            start_of_the_line = params:get('loop_start')
          end

          if current_number < start_of_the_line then
            -- regardless of loop mode or loop end, reset
            playing_forward = true
            reset()
            current_number_part = 2 
          end
        end

        
        -- if 0 set to 10
        local number_to_play = tonumber(string.sub(numbers[current_number], current_number_part, current_number_part))

        local blank_note = false
        local hold_note = false

        -- zero behaviour
        local zb = params:get("zero_behaviour")
        if number_to_play == 0 then
          number_to_play = 10

          if zb == 2 then
            blank_note = true
          end

          if zb == 3 then
            hold_note = true
          end
        end

        local octaves = params:get('octaves')
        if octaves > 1 then
          -- not sure if should be 8 or different way to shift octave up randomly
          number_to_play = util.clamp(number_to_play + (8 * math.random(0, octaves - 1)), 0, 48)
        end

        -- clamp to midi notes possible
        local note_num = util.clamp(notes[number_to_play], 0, 127)

        -- either hold because of zero behav or if NOT play duplicates and active
        if hold_note or (params:get('play_duplicates') == 2 and active_notes[#active_notes] == note_num) then
          -- hodl!
        else
          all_notes_off()

          local freq = MusicUtil.note_num_to_freq(note_num)

          -- Blank note and Trig Probablility
          if not blank_note and math.random(100) <= params:get("probability") then
              -- Audio engine out
              if params:get("out") == 1 or params:get("out") == 3 then
                engine.noteOn(note_num, freq, 0.75)
              elseif params:get("out") == 4 then
                  crow.output[1].volts = (note_num-60)/12
                  crow.output[2].execute()
              elseif params:get("out") == 5 then
                  crow.ii.jf.play_note((note_num-60)/12,5)
              end

              -- MIDI out
              if (params:get("out") == 2 or params:get("out") == 3) then
                  midi_device:note_on(note_num, 96, midi_channel)

                  --local note_off_time =
                  -- Note off timeout
                  if params:get("midi_note_length") < 4 then
                      notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * params:get("midi_note_length") * 0.25, 1)
                  end
              end

              table.insert(active_notes, note_num)
          end
        end

        redraw()
    else
    end
  end
end

function stop()
  running = false
  all_notes_off()
end

function start()
  running = true
end

function reset()
  current_number = loop_mode_on and params:get('loop_start') or 3
  current_number_part = 1
end

function clock.transport.start()
  start()
end

function clock.transport.stop()
  stop()
end

function clock.transport.reset()
  reset()
end

function midi_event(data)
  msg = midi.to_msg(data)
  if msg.type == "start" then
      clock.transport.reset()
      clock.transport.start()
  elseif msg.type == "continue" then
    if running then
      clock.transport.stop()
    else
      clock.transport.start()
    end
  end
  if msg.type == "stop" then
    clock.transport.stop()
  end
end

function build_midi_device_list()
  midi_devices = {}
  for i = 1,#midi.vports do
    local long_name = midi.vports[i].name
    local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
    table.insert(midi_devices,i..": "..short_name)
  end
end

function init()
  for i = 1, #MusicUtil.SCALES do
    table.insert(options.SCALE_NAMES, string.lower(MusicUtil.SCALES[i].name))
  end

  -- start clock tempo
  params:set("clock_tempo", 100)

  build_midi_device_list()
  build_numbers()

  notes_off_metro.event = all_notes_off

  init_params()
  
  hs.init()

  params:default()
  midi_device.event = midi_event

  clock.run(step)

  norns.enc.sens(1,12)
end

function init_params()

  params:add_separator("fibonacci")

  params:add_group("outs",3)
  params:add{type = "option", id = "out", name = "out",
    options = options.OUT,
    action = function(value)
      all_notes_off()
      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  params:add{type = "option", id = "midi_device", name = "midi out device",
    options = midi_devices, default = 1,
    action = function(value) midi_device = midi.connect(value) end}

  params:add{type = "number", id = "midi_out_channel", name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_off()
      midi_channel = value
    end}

  params:add_group("step",9)

  params:add{type = "option", id = "play_duplicates", name = "play duplicate numbers",
    options = {"yes", "no"},
    default = 1}

  params:add{type = "option", id = "zero_behaviour", name = "zero behaviour",
    options = {"play ten", "blank note", "hold note"},
    default = 1}

  params:add{type = "number", id = "step_div", name = "step division", min = 1, max = 16, default = 2}

  params:add{type = "option", id = "random_step_lengths", name = "random note lengths",
    options = {"no", "yes"},
    default = 1}

  params:add{type = "option", id = "midi_note_length", name = "midi note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}

  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = options.SCALE_NAMES, default = 5,
    action = function() build_scale() end}
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}
  params:add{type = "number", id = "octaves", name = "octaves",
    min = 1, max = 4, default = 1,
    action = function() build_scale() end}
  params:add{type = "number", id = "probability", name = "probability",
    min = 0, max = 100, default = 100,
  formatter = function(param) return param:get() .. '%' end}

  params:add_group("loop",3)

  params:add{type = "number", id = "loop_start", name = "loop start",
    min = 3, max = #numbers, default = 3,
    action = function() reset() end}

  params:add{type = "number", id = "loop_size", name = "loop size",
    min = 0, max = 32, default = 8}

  params:add{type = "option", id = "loop_end", name = "loop end",
    options = {"repeat", "reverse"}, default = 1}

  params:add_separator("Sound")

  params:add{type = "trigger", id = "stop", name = "stop",
    action = function() stop() reset() end}
  params:add{type = "trigger", id = "start", name = "start",
    action = function() start() end}
  params:add{type = "trigger", id = "reset", name = "reset",
    action = function() reset() end}
    
  params:add{type = "option", id = "random_sound_type", name = "random sound type",
    options = random_sound_types,
    default = 1
  }

  params:add{type = "trigger", id = "generate_preset", name = "generate preset",
    action = function() generate_synth_preset() end}
  
  params:add_separator("Molly")

  MollyThePoly.add_params()

  params:add_separator()
end

function enc(n, delta)
  if n==1 then
    -- change mode for pattern/sound
    mode = util.clamp(mode+delta,1,3)
  elseif mode == 1 then -- loop
    if loop_mode_on then
      if n==2 then
        params:delta('loop_start', delta)
      elseif n==3 then
        params:delta('loop_size', delta)
      end
    end
  elseif mode == 2 then -- pattern
    if n==2 then
      params:delta(main_params[main_sel], delta)
    elseif n==3 then
      params:delta(main_params[main_sel+1], delta)
    end
  elseif mode == 3 then --sound
    if n==2 then
      params:delta(snd_params[snd_sel], delta)
    elseif n==3 then
      params:delta(snd_params[snd_sel+1], delta)
    end
  end
  redraw()
end

function key(n,z)
    if z==1 then
        if mode == 1 then
          if n==1 then
            loop_mode_on = not loop_mode_on
            if loop_mode_on then
              params:set('loop_start', current_number)
            end
          elseif n==2 then
            if running then
              stop()
            else
              start()
            end
          elseif n==3 then
            reset()
          end
        elseif mode == 2 then
            if n==2 then
                main_sel = util.clamp(main_sel - 2,1,NUM_MAIN_PARAMS-1)
            elseif n==3 then
                main_sel = util.clamp(main_sel + 2,1,NUM_MAIN_PARAMS-1)
            end
        elseif mode == 3 then
            if n==2 then
                if snd_sel == 1 then
                  generate_synth_preset()
                else
                  snd_sel = util.clamp(snd_sel - 2,1,NUM_SND_PARAMS-1)
                end
            elseif n==3 then
                snd_sel = util.clamp(snd_sel + 2,1,NUM_SND_PARAMS-1)
            end
        end
    end

    redraw()
end

function redraw()
  screen.clear()
  screen.line_width(1)
  screen.aa(0)

  -- defaults
  screen.font_size(8)
  screen.font_face(1)
  screen.level(4)
  screen.move(0,10)
  screen.text(mode_names[mode])

  if mode==2 then
    -- settings status dots
    screen.move(0, 20)
    i = 1
    repeat
      screen.level(main_sel == i and 15 or 2)
      screen.text('.')
      i = i + 2
    until i > #main_params

    screen.level(1)
    screen.move(0,30)
    screen.text(main_names[main_sel])
    screen.level(15)
    screen.move(0,40)
    screen.text(params:string(main_params[main_sel]))
    screen.level(1)
    screen.move(0,50)
    screen.text(main_names[main_sel+1])
    screen.level(15)
    screen.move(0,60)
    screen.text(params:string(main_params[main_sel+1]))
  elseif mode==3 then
    -- settings status dots
    screen.move(0, 20)
    i = 1
    repeat
      screen.level(snd_sel == i and 15 or 2)
      screen.text('.')
      i = i + 2
    until i > #snd_params

    screen.level(1)
    screen.move(0,30)
    screen.text(snd_names[snd_sel])
    screen.level(15)
    screen.move(0,40)
    screen.text(params:string(snd_params[snd_sel]))
    screen.level(1)
    screen.move(0,50)
    screen.text(snd_names[snd_sel+1])
    screen.level(15)
    screen.move(0,60)
    if snd_params[snd_sel+1] == 'generate_preset' then
      screen.text('press k2')
    else
      screen.text(params:string(snd_params[snd_sel+1]))
    end
  end

  -- previous numbers
  if mode == 1 then
    screen.font_size(7)
    screen.font_face(15)
    screen.level(2)
    screen.move(0,15)
    screen.text(numbers[current_number - 2])
    screen.level(7)
    screen.move_rel(1, 0)
    screen.text('+')

    screen.move(0,23)
    screen.level(2)
    screen.text(numbers[current_number - 1])

    -- current number
    screen.move(0, 37)
    screen.font_size(9)
    screen.font_face(15)

    local number_playing = numbers[current_number]

    for i=1,string.len(number_playing) do
      local number_part_playing = tonumber(string.sub(number_playing, i, i))
      if i == current_number_part then
          screen.level(15)
          --screen.font_face(7) -- bold
      else
          screen.level(1)
          --screen.font_face(5) -- normal
      end
      screen.text(number_part_playing)

      if i < #numbers then
        screen.move_rel(1, 0)
      end

      -- new line?
      if i == 9 then
          --screen.move(50, 42)
      end
    end

    -- loop mode
    screen.move(0, 60)
    screen.font_size(7)
    if loop_mode_on then
      screen.level(10)
      screen.text(numbers[params:get('loop_start')])
      screen.text(' -')

      local limit = params:get('loop_start') + params:get('loop_size') 
      limit = limit > #numbers and #numbers or limit
      screen.text(numbers[limit])
    else
      screen.level(2)
      screen.text('K1 > LOOP')
    end
  end

  for i=1,10 do
    local number_to_play = tonumber(string.sub(numbers[current_number], current_number_part, current_number_part))
    number_to_play = number_to_play == 0 and 10 or number_to_play
    local light = number_to_play == i and 15 or 2
    draw_cube(100 + (i > 5 and 10 or 0), 0+((i > 5 and i - 5 or i)*10), light)
  end
  screen.update()
end

function draw_cube(m, n, light)
  screen.rect(m, n, 6, 6) -- (x,y,width,height)
  screen.level(light)
  screen.stroke()
end

function cleanup()
end