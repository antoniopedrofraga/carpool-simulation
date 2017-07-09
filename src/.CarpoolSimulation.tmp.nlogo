__includes ["bdi.nls" "communication.nls"]

breed [cars car]
breed [persons person]

globals
[
  grid-x-inc               ;; the amount of patches in between two roads in the x direction
  grid-y-inc               ;; the amount of patches in between two roads in the y direction
  acceleration             ;; the constant that controls how much a car speeds up or slows down by if
                           ;; it is to accelerate or decelerate
  phase                    ;; keeps track of the phase
  num-cars-stopped         ;; the number of cars that are stopped during a single pass thru the go procedure
  current-intersection     ;; the currently selected intersection
  carpoolers               ;; a list of carpoolers
  goal-candidates

  ;; patch agentsets
  intersections ;; agentset containing the patches that are intersections
  roads         ;; agentset containing the patches that are roads
  intersection-patches

  high-populated-area

  roadsA
  roadsB

  upRoad
  leftRoad
  downRoad
  rightRoad

  num-waiting-persons
  num-persons-carpooling
  num-cars-carpooling
  num-parked-cars
  accidents-list

  semaphores
  semaphore-goals

  xop-priority
  xdp-priority
  yop-priority
  ydp-priority

  mouse-was-down?

  log-file
]

cars-own
[
  speed     ;; the speed of the turtle
  up-car?   ;; true if the turtle moves downwards and false if it moves to the right
  wait-time ;; the amount of time since the last time a turtle has moved
  capacity  ;; the car capacity
  is-carpooler ;; the car can carpool
  work      ;; the patch where they work
  house     ;; the patch where they live
  current-path ;;the path to take
  goal      ;; where am I currently headed
  parked

  parking-elapsed-time
  parking-limit-time

  passengers ;; passengers

  intentions
  beliefs
  incoming-queue
]
persons-own
[
  wait-time ;; the amount of time since the last time a turtle has moved
  limit-wait-time ;; the limit amount of waiting time

  work      ;; the patch where a person works
  house     ;; the patch where a person lives
  goal      ;; where am I currently headed

  carpooler ;; carpooler car
  carpooled
  response-received

  intentions
  beliefs
  incoming-queue
]

patches-own
[
  intersection?   ;; true if the patch is at the intersection of two roads
  green-light-up? ;; true if the green light is above the intersection.  otherwise, false.
                  ;; false for a non-intersection patches.
  my-row          ;; the row of the intersection counting from the upper left corner of the
                  ;; world.  -1 for non-intersection patches.
  my-column       ;; the column of the intersection counting from the upper left corner of the
                  ;; world.  -1 for non-intersection patches.
  my-phase        ;; the phase for the intersection.  -1 for non-intersection patches.
  auto?           ;; whether or not this intersection will switch automatically.
                  ;; false for non-intersection patches.
  actual-color

  accident-current-time
  accident-limit-time
]


;;;;;;;;;;;;;;;;;;;;;;
;; Setup Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Initialize the display by giving the global and patch variables initial values.
;; Create num-cars of turtles if there are enough road patches for one turtle to
;; be created per road patch.
to setup

  clear-ticks
  clear-turtles
  clear-patches
  clear-drawing
  clear-all-plots
  clear-output

  ifelse small-world [
    set-patch-size 10
    resize-world -30 30 -30 30
  ][
    set-patch-size 16
    resize-world -18 18 -18 18
  ]
  setup-globals
  setup-patches  ;; ask the patches to draw themselves and set up a few variables
  setup-log

  ;; Make an agentset of all patches where there can be a house or road
  ;; those patches with the background color shade of brown and next to a road
  set goal-candidates patches with [
    pcolor = 38 and any? neighbors with [ pcolor = white ]
  ]
  set intersection-patches patches with [
    member? patch-at 0 1 intersections
    or
    member? patch-at -1 0 intersections
    or
    member? patch-at -1 1 intersections
    or
    member? patch-at 0 0 intersections
  ]

  if priority-areas [
    set high-populated-area get-high-populated-area xop-priority yop-priority xdp-priority ydp-priority
    let possible-goal one-of high-populated-area with [member? one-of [neighbors4] of self goal-candidates]
    if possible-goal = nobody [
      user-message (word
      "No possible goal was found"
      ".  Either change the priority area "
      "by clicking on Select Priority Area "
      "button, or turn off priority area button "
      "by disbaling the Priority Area switcher.\n"
      "The setup has stopped.")
    stop
    ]
  ]
  ask patches [
    set actual-color pcolor
  ]
  ask one-of intersections [ become-current ]

  if (num-cars > count roads) [
    user-message (word
      "There are too many cars for the amount of "
      "road.  Either increase the amount of roads "
      "by increasing the GRID-SIZE-X or "
      "GRID-SIZE-Y sliders, or decrease the "
      "number of cars by lowering the NUM-CAR slider.\n"
      "The setup has stopped.")
    stop
  ]

  if (count turtles * 2 > count goal-candidates) [
    user-message (word
      "There are too many persons and cars for the amount of "
      "work and house candidates.  Either increase the amount of roads "
      "by increasing the GRID-SIZE-X or "
      "GRID-SIZE-Y sliders, or decrease the "
      "number of cars/persons by lowering the NUM-CAR or NUM-PERSONS slider.\n"
      "The setup has stopped.")
    stop
  ]

  ;; Now create the cars and have each created car call the functions setup-cars and set-car-color
  create-cars num-cars [
    setup-cars
    set-car-color ;; slower turtles are blue, faster ones are colored cyan
    record-data
    setup-goal

    set current-path get-path
    go-to-goal
  ]
  set carpoolers cars with [ is-carpooler = true ]

  create-persons num-persons [
    set color black
    setup-limit-wait-time
    setup-goal

    setup-persons
    ask-for-carpool
  ]
  ;; give the turtles an initial speed
  ask cars [ set-car-speed ]

  reset-ticks
end
to setup-limit-wait-time
  let discrepancy (random waiting-discrepancy + 1) / 100
  set limit-wait-time 0
    ifelse random 2 = 0
      [ set limit-wait-time ticks-of-waiting + (ticks-of-waiting * discrepancy) ]
      [ set limit-wait-time ticks-of-waiting - (ticks-of-waiting * discrepancy) ]
end
;; Setup goal fro cars and persons
to setup-goal
  ifelse priority-areas  [
    let area high-populated-area

    let probability-house random 100 < %-population
    ifelse probability-house [
      set house one-of goal-candidates with [member? self area]
    ][
      set house one-of goal-candidates with [not member? self area]
    ]
    let probability-work random 100 < %-population
    ifelse probability-work [
      set work one-of goal-candidates with [ self != [ house ] of myself and member? self area ]
    ][
      set work one-of goal-candidates with [ self != [ house ] of myself and not member? self area ]
    ]
    set goal work
  ] [
    ;; choose at random a location for the house
    set house one-of goal-candidates
    ;; choose at random a location for work, make sure work is not located at same location as house
    set work one-of goal-candidates with [ self != [ house ] of myself ]
    set goal work
  ]
end
to setup-log
  if log-write [
    set log-file (word "../logs/" log-file-name ".log")
    ifelse not file-exists? log-file [
      file-open log-file
      file-print "The simulation started under these conditions:"
      file-print ""
      file-print ""
      file-print (word "Number of x-grids:" grid-size-x ", number of y-grids:" grid-size-y
        ", semaphores:" power? ", small world:" small-world ", number of cars:" num-cars ", % of carpoolers:" %-carpoolers
        ", number of passengers:" num-passengers ", person ticks of waiting:" ticks-of-waiting ", person waiting discrepancy:" waiting-discrepancy "%"
        ", priority area:" priority-areas " with a population % of " %-population ", priority area:" priority-areas
        ", possibility of accidents:" accidents " with a accident % of " accident-probability ", an average accident time of " ticks-of-accident " ticks "
        "and a discrepancy of " accident-time-discrepancy "%"
        ", possibility of parking:" parking " with a parking % of " parking-probability ", an average parking time of " ticks-of-parking " ticks "
        "and a discrepancy of " parking-time-discrepancy "%")
      file-print ""
      file-print ""
      file-print "Agents LOG:"
      file-print ""
    ][
      user-message (word
      "Log file already exists"
      ".  Either change the log-file name "
      "or delete the existing one. \n"
      "The setup has stopped.")
    ]
  ]
end
;; Initialize the global variables to appropriate values
to setup-globals
  set current-intersection nobody ;; just for now, since there are no intersections yet
  set phase 0
  set num-cars-stopped 0
  set grid-x-inc world-width / grid-size-x
  set grid-y-inc world-height / grid-size-y
  set num-cars-carpooling 0
  set num-persons-carpooling 0
  set num-waiting-persons 0
  set num-parked-cars 0
  set mouse-was-down? false

  set accidents-list []

  ;; don't make acceleration 0.1 since we could get a rounding error and end up on a patch boundary
  set acceleration 0.099
end

;; Make the patches have appropriate colors, set up the roads and intersections agentsets,
;; and initialize the traffic lights to one setting
to setup-patches
  ;; initialize the patch-owned variables and color the patches to a base-color
  ask patches [
    set intersection? false
    set auto? false
    set green-light-up? true
    set my-row -1
    set my-column -1
    set my-phase -1
    set pcolor brown + 3

    set accident-current-time 1
    set accident-limit-time 0
  ]

  ;; initialize the global variables that hold patch agentsets
  set roads patches with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0) or
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set roadsA roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)
  ]
  set roadsB roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set upRoad roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0)
  ]
  set rightRoad roads with [
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)
  ]
  set downRoad roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0)
  ]
  set leftRoad roads with [
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set intersections roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set semaphores roads with [
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 2)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 3)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor + 2) mod grid-y-inc) = 1))
  ]
  set semaphore-goals roads with [
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 2)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 3)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor - 1) mod grid-y-inc) = 0)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor + 1) mod grid-y-inc) = 1)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor + 2) mod grid-y-inc) = 1))
  ]
  ask roads [set pcolor white ]
  ask intersections [ set pcolor white ]

  setup-intersections
end

;; Give the intersections appropriate values for the intersection?, my-row, and my-column
;; patch variables.  Make all the traffic lights start off so that the lights are red
;; horizontally and green vertically.
to setup-intersections
  ask intersections [
    set intersection? true
    set green-light-up? true
    set my-phase 0
    set auto? true
    set my-row floor ((pycor + max-pycor) / grid-y-inc)
    set my-column floor ((pxcor + max-pxcor) / grid-x-inc)
    set-signal-colors
  ]
end

;; Initialize the turtle variables to appropriate values and place the turtle on an empty road patch.
to setup-cars  ;; turtle procedure
  set speed 0
  set wait-time 0
  set capacity num-passengers
  set is-carpooler ifelse-value (random 100 < %-carpoolers) [true] [false]
  ifelse (is-carpooler = true) [ set shape "car-carpooling" ][set shape "car"]
  set passengers 0
  set intentions []
  set incoming-queue []
  set parked false
  set parking-elapsed-time 1
  set parking-limit-time 0
  put-on-empty-road
  ifelse intersection? [
    ifelse random 2 = 0
      [ set up-car? true ]
      [ set up-car? false ]
  ]
  [ ; if the turtle is on a vertical road (rather than a horizontal one)
    ifelse (floor ((pxcor + max-pxcor - floor(grid-x-inc - 1)) mod grid-x-inc) = 0)
      [ set up-car? true ]
      [ set up-car? false ]
  ]
  ifelse up-car?
    [ set heading 180 ]
    [ set heading 90 ]
  go-to-goal
end

to setup-persons
  set shape "person"
  move-to house

  set response-received false
  set carpooler nobody
  set intentions []
  set incoming-queue []
end

;; Find a road patch without any turtles on it and place the turtle there.
to put-on-empty-road  ;; turtle procedure
  move-to one-of roads with [ not any? cars-on self ]
end


;;;;;;;;;;;;;;;;;;;;;;;;
;; Runtime Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;;;

;; Run the simulation
to go

  ask current-intersection [ update-variables ]
  ask turtles [execute-intentions]

  ;; have the intersections change their color
  set-signals
  set num-cars-stopped 0

  ;; set the cars’ speed, move them forward their speed, record data for plotting,
  ;; and set the color of the cars to an appropriate color based on their speed
  ask cars [
    record-data     ;; record data for plotting
    set-car-color   ;; set color to indicate speed
  ]
  label-subject ;; if we're watching a car, have it display its goal
  next-phase ;; update the phase and the global clock
  if show-accident-roads [
    ask patches with [ accident-current-time + 1 >= accident-limit-time  and accident-current-time < accident-limit-time and not member? self semaphores] [
      set pcolor actual-color
    ]
  ]
  ask patches with [ accident-current-time < accident-limit-time] [
    set accident-current-time accident-current-time + 1
  ]
  let index 0
  while [index < length accidents-list ] [
    let accident item index accidents-list
    ifelse accident - 1 <= 0 [
      set accidents-list remove-item index accidents-list
    ][
      set accidents-list replace-item index accidents-list (accident - 1)
      set index index + 1
    ]
  ]
  tick
end

to choose-current
  if mouse-down? [
    let x-mouse mouse-xcor
    let y-mouse mouse-ycor
    ask current-intersection [
      update-variables
      ask patch-at -1 1 [ set plabel "" ] ;; unlabel the current intersection (because we've chosen a new one)
    ]
    ask min-one-of intersections [ distancexy x-mouse y-mouse ] [
      become-current
    ]
    display
    stop
  ]
end

to choose-priority-area
  let complete? false

  if not complete? [
    if mouse-down? and not mouse-was-down? [
      set xop-priority mouse-xcor
      set yop-priority mouse-ycor
      set mouse-was-down? true
    ]
    if not mouse-down? and mouse-was-down? [
      set xdp-priority mouse-xcor
      set ydp-priority mouse-ycor
      set mouse-was-down? false
      set complete? true
      ask patches [
        set pcolor actual-color
      ]
      stop
    ]
  ]
  while[mouse-down? and mouse-was-down?] [
    let area get-high-populated-area xop-priority yop-priority mouse-xcor mouse-ycor
    let not-area patches with [not member? self area]
    ask area [
      set pcolor orange
    ]
    ask not-area [
      set pcolor actual-color
    ]
    display
    ]
end
to-report mouse-clicked?
  report (mouse-was-down? = true and not mouse-down?)
end

;; Set up the current intersection and the interface to change it.
to become-current ;; patch procedure
  set current-intersection self
  set current-phase my-phase
  set current-auto? auto?
  ask patch-at -1 1 [
    set plabel-color black
    set plabel "current"
  ]
end

;; update the variables for the current intersection
to update-variables ;; patch procedure
  set my-phase current-phase
  set auto? current-auto?
end

;; have the traffic lights change color if phase equals each intersections' my-phase
to set-signals
  ask intersections with [ auto? and phase = floor ((my-phase * ticks-per-cycle) / 100) ] [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; This procedure checks the variable green-light-up? at each intersection and sets the
;; traffic lights to have the green light up or the green light to the left.
to set-signal-colors  ;; intersection (patch) procedure
  ifelse power? [
    ifelse green-light-up? [
      ask patch-at -1 -1 [ set pcolor red ]
      ask patch-at 2 0 [ set pcolor red ]
      ask patch-at 0 1 [ set pcolor green ]
      ask patch-at 1 -2 [ set pcolor green ]
    ]
    [
      ask patch-at -1 -1 [ set pcolor green ]
      ask patch-at 2 0 [ set pcolor green ]
      ask patch-at 0 1 [ set pcolor red ]
      ask patch-at 1 -2 [ set pcolor red ]
    ]
  ]
  [
    ask patch-at -1 -1 [ set pcolor white]
    ask patch-at 2 0 [ set pcolor white ]
    ask patch-at 0 1 [ set pcolor white ]
    ask patch-at 1 -2 [ set pcolor white ]
  ]
end

;; set the turtles' speed based on whether they are at a red traffic light or the speed of the
;; turtle (if any) on the patch in front of them
to set-car-speed  ;; turtle procedure
  let at-accident-patch [accident-current-time] of patch-here < [accident-limit-time] of patch-here
  ifelse pcolor = red or at-accident-patch [
    set speed 0
  ]
  [
    ifelse (member? patch-here roadsA) [
        ifelse (member? patch-here upRoad)
        [ set-speed 0 1 ]
        [ set-speed 1 0 ]
      ] [
        ifelse (member? patch-here downRoad)
        [ set-speed 0 -1 ]
        [ set-speed -1 0 ]
      ]
  ]
end

;; set the speed variable of the turtle to an appropriate value (not exceeding the
;; speed limit) based on whether there are turtles on the patch in front of the turtle
to set-speed [ delta-x delta-y ]  ;; turtle procedure
  ;; get the turtles on the patch in front of the turtle
  let cars-ahead cars-at delta-x delta-y

  ;; if there are turtles in front of the turtle, slow down
  ;; otherwise, speed up
  ifelse any? cars-ahead with [parked = false] [
    ifelse any? (cars-ahead with [ up-car? != [ up-car? ] of myself and parked = false]) [
      set speed 0
    ]
    [
      set speed [speed] of one-of cars-ahead with [parked = false]
      slow-down
    ]
  ]
  [ speed-up ]
end

;; decrease the speed of the car
to slow-down  ;; turtle procedure
  ifelse speed <= 0
    [ set speed 0 ]
    [ set speed speed - acceleration ]
end

;; increase the speed of the car
to speed-up  ;; turtle procedure
  ifelse speed > speed-limit
    [ set speed speed-limit ]
    [ set speed speed + acceleration ]
end

;; set the color of the car to a different color based on how fast the car is moving
to set-car-color  ;; turtle procedure
  ifelse speed < (speed-limit / 2)
    [ set color blue ]
    [ set color cyan - 2 ]
end

;;; Main intention that listens and responds to messages.
to wait-for-messages
  let msg get-message
  if msg = "no_message" [stop]
  let sender get-sender msg
  if get-performative msg = "query-if" and get-content msg = "able-to-carpool?" [
    ifelse (passengers < num-passengers - 1) [
      let text (word "responded with yes, he still has " (passengers + 1) "/" num-passengers " passengers")
      write-in-log text
      send add-content "yes" create-reply "inform" msg
      if passengers = 0 [ set num-cars-carpooling num-cars-carpooling + 1 ]
      set passengers passengers + 1
      set num-persons-carpooling num-persons-carpooling + 1
    ][
      let text (word "responded with no, he already has " (passengers + 1) "/" num-passengers " passengers")
      write-in-log text
      send add-content "no" create-reply "inform" msg
    ]
  ]
  if get-performative msg = "inform" [
    if (get-content msg = "was-left") [

      let text (word "received an inform message from " sender ", he was left.")
      write-in-log text

      if passengers = 1 [ set num-cars-carpooling num-cars-carpooling - 1 ]
      set passengers passengers - 1
      set num-persons-carpooling num-persons-carpooling - 1
    ]
  ]
end
to wait-for-responses
  let msg get-message
  if msg = "no_message" [stop]
  let sender get-sender msg
  if get-performative msg = "inform" [
    if (get-content msg = "yes") [
      set shape "face happy"
      set color yellow
      set carpooler turtle (read-from-string sender)
      set response-received true
      set wait-time 0
      set num-waiting-persons num-waiting-persons + 1
      add-intention "pick-me-up" "picked-up"
      send add-content "carpool" create-reply "request" msg
    ]
    if (get-content msg = "no") [
      set carpooler nobody
      set response-received true
      ask-for-carpool
    ]
  ]
end

;; keep track of the number of stopped cars and the amount of time a car has been stopped
;; if its speed is 0
to record-data  ;; turtle procedure
  ifelse speed = 0 [
    set num-cars-stopped num-cars-stopped + 1
    set wait-time wait-time + 1
  ]
  [ set wait-time 0 ]
end

to change-light-at-current-intersection
  ask current-intersection [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; cycles phase to the next appropriate value
to next-phase
  ;; The phase cycles from 0 to ticks-per-cycle, then starts over.
  set phase phase + 1
  if phase mod ticks-per-cycle = 0 [ set phase 0 ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Intention Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Set the intention of finding a carpooler
to ask-for-carpool
  add-intention "find-a-carpooler" "carpool-found"
end
to pick-me-up
  let pickable-group [neighbors4] of carpooler
  if member? patch-here pickable-group [
    hide-turtle
  ]
end
to leave-me-there
  let pickable-group [neighbors4] of carpooler
  if member? goal pickable-group [
    move-to goal
    set shape "person"
    set color black
    show-turtle
  ]
end
to find-a-carpooler
  let start ifelse-value (work = goal) [ house ][ work ]
  set start one-of ([ neighbors4 ] of start) with [member? self roads]
  let finish goal
  set finish one-of ([ neighbors4 ] of finish) with [member? self roads]

  let suitable-carpooler one-of carpoolers with [ am-i-a-suitable-carpooler self start finish ]
  if suitable-carpooler != nobody [
    let text word "sent a query-if to " suitable-carpooler
    write-in-log text
    set response-received false
    add-intention "wait-for-responses" "response-was-received"
    send add-receiver ([who] of suitable-carpooler) add-content "able-to-carpool?" create-message "query-if"
  ]
  set wait-time wait-time + 1
  if wait-time > 0.75 * limit-wait-time [
    set shape "face sad"
    set color blue
  ]
  if wait-time > limit-wait-time [
    set wait-time 0
    setup-goal
    move-to house
    set shape "person"
    set color black

    let text (word "changed his home to " house ", and work to " work ". He waited for " limit-wait-time " ticks before taking this action.")
    write-in-log text

    setup-limit-wait-time
  ]
end
to-report am-i-a-suitable-carpooler [candidate start finish]
  let start-position position start ([current-path] of candidate)
  if start-position = false [ report false ]
  let finish-position position finish [current-path] of candidate
  if finish-position = false [ report false ]
  report start-position < finish-position
end
;; Set the intention to go to goal
to go-to-goal
  add-intention "next-patch-to-goal" "at-goal"
end
to set-path
  set current-path get-path
  go-to-goal
end
to next-patch-to-goal
  wait-for-messages
  face next-patch ;; car heads towards its goal
  set-car-speed
  fd speed
  if accidents and speed > 0 [
    let random-value random-float 100
    let is-an-accident random-value < accident-probability
    if is-an-accident [
      cut-the-road patch-here
    ]
  ]
  if parking and speed > 0 and not member? patch-here intersection-patches and not member? patch-here semaphores [
    let random-value random-float 100
    set parked random-value < parking-probability
    if parked [
      let discrepancy (random accident-time-discrepancy) / 100
      set parking-elapsed-time 0
      set parking-limit-time ifelse-value (random 2 = 0)
      [ ticks-of-parking + ticks-of-parking * discrepancy ]
      [ ticks-of-parking - ticks-of-parking * discrepancy ]
      hide-turtle
      write-in-log (word "parked at " patch-here " for " parking-limit-time " ticks.")
      add-intention "park" "parking-time-elapsed"
      set num-parked-cars num-parked-cars + 1
    ]
  ]
end
to park
  if show-parking-patches [
    ask patch-here [
      set pcolor gray
    ]
  ]
  set parking-elapsed-time parking-elapsed-time + 1
end
to cut-the-road [ accident-patch ]
  let discrepancy (random accident-time-discrepancy) / 100
  let accident-time ifelse-value (random 2 = 0)
  [ ticks-of-accident + ticks-of-accident * discrepancy ]
  [ ticks-of-accident - ticks-of-accident * discrepancy ]

  let text (word "had an accident at patch " accident-patch ", he has to wait for " accident-time " ticks before he can drive again. The whole road was cut.")
  write-in-log text

  set accidents-list lput accident-time accidents-list

  ifelse member? accident-patch intersection-patches [
    let intersection-neighbors ([neighbors] of accident-patch) with [member? self intersection-patches]
    ask (patch-set accident-patch intersection-neighbors) [
        set accident-current-time 0
        set accident-limit-time accident-time
      ]
    if show-accident-roads [
      ask (patch-set accident-patch intersection-neighbors) [
        set pcolor yellow
      ]
    ]
  ][
    let old-patch accident-patch
    while [not member? accident-patch intersection-patches] [
      ask accident-patch [
        set accident-current-time 0
        set accident-limit-time accident-time
      ]
      if show-accident-roads [
        ask accident-patch [
          set pcolor yellow
        ]
      ]
      set accident-patch ifelse-value (member? accident-patch upRoad or member? accident-patch downRoad) [([patch-at 0 1] of accident-patch)][([patch-at 1 0] of accident-patch)]
    ]
    while [not member? old-patch intersection-patches] [
      ask old-patch [
        set accident-current-time 0
        set accident-limit-time accident-time
      ]
      if show-accident-roads [
        ask old-patch [
          set pcolor yellow
        ]
      ]
      set old-patch ifelse-value (member? old-patch upRoad or member? old-patch downRoad) [([patch-at 0 -1] of old-patch)][([patch-at -1 0] of old-patch)]
    ]
  ]

end
;; establish goal of driver (house or work) and move to next patch along the way
to-report next-patch
  let choice item 0 current-path
  report choice
end

to watch-a-car
  stop-watching ;; in case we were previously watching another car
  watch one-of cars
  ask subject [

    inspect self
    set size 2 ;; make the watched car bigger to be able to see it

    ask house [
      set pcolor yellow          ;; color the house patch yellow
      set plabel-color yellow    ;; label the house in yellow font
      set plabel "house"
      inspect self
    ]
    ask work [
      set pcolor orange          ;; color the work patch orange
      set plabel-color orange    ;; label the work in orange font
      set plabel "work"
      inspect self
    ]
    set label [ plabel ] of goal ;; car displays its goal
  ]
end

to stop-watching
  ;; reset the house and work patches from previously watched car(s) to the background color
  ask patches with [ pcolor = yellow or pcolor = orange ] [
    stop-inspecting self
    set pcolor 38
    set plabel ""
  ]
  ;; make sure we close all turtle inspectors that may have been opened
  ask cars [
    set size 1
    set label ""
    stop-inspecting self
  ]
  reset-perspective
end
to close-file
  if file-exists? log-file [
    file-print ""
    file-print ""
    file-print (word "The simulation runned for " ticks " ticks and has ended.")
  ]
  file-close
end
to label-subject
  if subject != nobody [
    ask subject [
      if goal = house [ set label "house" ]
      if goal = work [ set label "work" ]
    ]
  ]
end

to-report get-path
  let path []
  set path lput patch-here path
  while [last path != goal] [
    let current-patch last path
    let patch-to-analyze current-patch
    let index 1
    while [not member? patch-to-analyze semaphores] [
      if (member? patch-to-analyze [ neighbors4 ] of goal) [
        set path lput patch-to-analyze path
        report path
      ]
      set patch-to-analyze ifelse-value (member? patch-to-analyze roadsA) [
        ifelse-value (member? patch-to-analyze upRoad)
        [ ([patch-at 0 index] of current-patch) ]
        [ ([patch-at index 0] of current-patch) ]
      ] [
        ifelse-value (member? patch-to-analyze downRoad)
        [ ([patch-at 0 (index * -1)] of current-patch) ]
        [ ([patch-at (index * -1) 0] of current-patch) ]
      ]
      set index index + 1

      set path lput patch-to-analyze path
    ]

    let intersection (patch-set [patch-at -1 2] of patch-to-analyze [patch-at 1 1] of patch-to-analyze [patch-at -2 0] of patch-to-analyze [patch-at 0 -1] of patch-to-analyze) with [member? self intersections]
    let possible-goals (patch-set [patch-at 1 1] of intersection [patch-at 0 -2] of intersection [patch-at -1 0] of intersection [patch-at 2 -1] of intersection)
    let current-choices possible-goals with [ not member? self path or member? self intersection-patches ]
    let semaphore-goal min-one-of current-choices [ distance [ goal ] of myself ]

    set path get-path-at-intersection path patch-to-analyze semaphore-goal
  ]
  report path
end

to write-in-log [ text ]
  if log-write [
     file-show text
  ]
end

;; intentions reporters
to-report at-goal
  if parked [
    report true
  ]
  if patch-here = (item 0 current-path) [
    if goal = house and (member? patch-here [ neighbors4 ] of house) [
      write-in-log "arrived to work and a new path was recalculated."
      set goal work
      set-path
      report true
    ]
    if goal = work and (member? patch-here [ neighbors4 ] of work) [
      write-in-log "arrived to his house and a new path was recalculated."
      set goal house
      set-path
      report true
    ]
    set current-path but-first current-path
    go-to-goal
    report true
  ]
  report false
end
to-report response-was-received
  report response-received = true
end
to-report carpool-found
  report carpooler != nobody
end
to-report picked-up
  if (hidden?) [
    add-intention "leave-me-there" "was-left"
    set num-waiting-persons num-waiting-persons - 1
    report true
  ]
  report false
end
to-report was-left
  if (hidden? = false) [
    if goal = house and (member? [patch-here] of carpooler [ neighbors4 ] of house) [
      set goal work
    ]
    if goal = work and (member? [patch-here] of carpooler [ neighbors4 ] of work) [
      set goal house
    ]
    send add-receiver ([who] of carpooler) add-content "was-left" create-message "inform"
    set carpooler nobody
    report true
  ]
  report false
end
to-report get-path-at-intersection [intersection-path current-patch goal-patch]
  let candidates ifelse-value (member? current-patch roadsA) [
     ifelse-value (member? current-patch upRoad)
    [(patch-set current-patch  ([patch-at 0 1] of current-patch) ([patch-at 0 2] of current-patch))]
     [(patch-set current-patch ([patch-at 1 0] of current-patch) ([patch-at 2 0] of current-patch))]
  ][
    ifelse-value (member? current-patch downRoad)
    [(patch-set current-patch ([patch-at 0 -1] of current-patch) ([patch-at 0 -2] of current-patch))]
    [(patch-set current-patch ([patch-at -1 0] of current-patch) ([patch-at -2 0] of current-patch))]
  ]
  let direction ifelse-value (member? current-patch roadsA) [
     ifelse-value (member? current-patch upRoad)
    ["up"]
     ["right"]
  ][
    ifelse-value (member? current-patch downRoad)
    ["down"]
    ["left"]
  ]

  let patch-to-analyze current-patch
  while [patch-to-analyze != goal-patch][
    ifelse member? patch-to-analyze candidates and patch-to-analyze != min-one-of candidates [ distance [ goal-patch ] of self ][
      ifelse (direction = "up" or direction = "right") [
        ifelse (direction = "up")
        [ set intersection-path lput ([patch-at 0 1] of patch-to-analyze) intersection-path ]
        [ set intersection-path lput ([patch-at 1 0] of patch-to-analyze) intersection-path ]
      ] [
        ifelse (direction = "down")
        [ set intersection-path lput ([patch-at 0 -1] of patch-to-analyze) intersection-path ]
        [ set intersection-path lput ([patch-at -1 0] of patch-to-analyze) intersection-path ]
      ]
    ][
      let next ifelse-value (member? patch-to-analyze ([neighbors4] of goal-patch))
      [ goal-patch ]
      [ min-one-of ([neighbors4] of patch-to-analyze) [ distance [ goal-patch ] of self ] ]
      set intersection-path lput next intersection-path
    ]
    set patch-to-analyze last intersection-path
  ]
  report intersection-path
end
to-report parking-time-elapsed
  if parking-elapsed-time >= parking-limit-time [
    show-turtle
    set parked false
    go-to-goal
    ask patch-here [
      set pcolor white
    ]
    set num-parked-cars num-parked-cars - 1
    write-in-log "is driving again."
    report true
  ]
  report false
end
to-report get-high-populated-area [x1 y1 x2 y2]
  report ifelse-value (x1 >= x2) [
      ifelse-value (y1 >= y2) [
        patches with [pxcor <= x1 and pxcor >= x2 and pycor <= y1 and pycor >= y2]
      ][
        patches with [pxcor <= x1 and pxcor >= x2 and pycor >= y1 and pycor <= y2]
      ]
      ] [
      ifelse-value (y1 >= y2) [
        patches with [pxcor >= x1 and pxcor <= x2 and pycor <= y1 and pycor >= y2]
      ][
        patches with [pxcor >= x1 and pxcor <= x2 and pycor >= y1 and pycor <= y2]
      ]
  ]
end
; António Pedro Fraga, Pedro Martins and Luís Oliveira developed this project in 2017 based on the Traffic Simulation Model developed by Uri Wilensky in 2008.
@#$#@#$#@
GRAPHICS-WINDOW
590
10
1208
629
-1
-1
10.0
1
15
1
1
1
0
1
1
1
-30
30
-30
30
1
1
1
ticks
30.0

PLOT
1665
10
1883
185
Average Wait Time of Cars
Time
Average Wait
0.0
100.0
0.0
5.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [wait-time] of cars"

PLOT
1442
8
1658
183
Average Speed of Cars
Time
Average Speed
0.0
100.0
0.0
1.0
true
false
"set-plot-y-range 0 speed-limit" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [speed] of cars"

SLIDER
110
10
205
43
grid-size-y
grid-size-y
1
9
7.0
1
1
NIL
HORIZONTAL

SLIDER
10
10
104
43
grid-size-x
grid-size-x
1
9
7.0
1
1
NIL
HORIZONTAL

SWITCH
210
10
315
43
power?
power?
0
1
-1000

SLIDER
10
45
205
78
num-cars
num-cars
1
400
100.0
1
1
NIL
HORIZONTAL

PLOT
1219
7
1433
182
Stopped Cars
Time
Stopped Cars
0.0
100.0
0.0
100.0
true
false
"set-plot-y-range 0 num-cars" ""
PENS
"default" 1.0 0 -16777216 true "" "plot num-cars-stopped"

BUTTON
485
45
570
78
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
485
10
569
43
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
330
45
475
78
speed-limit
speed-limit
0.1
1
0.5
0.1
1
NIL
HORIZONTAL

MONITOR
1280
640
1385
685
Current Phase
phase
3
1
11

SLIDER
330
10
475
43
ticks-per-cycle
ticks-per-cycle
1
100
25.0
1
1
NIL
HORIZONTAL

SLIDER
460
175
575
208
current-phase
current-phase
0
99
0.0
1
1
%
HORIZONTAL

BUTTON
15
220
160
253
Change light
change-light-at-current-intersection
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SWITCH
330
175
445
208
current-auto?
current-auto?
0
1
-1000

BUTTON
165
220
310
253
Select intersection
choose-current
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
330
220
455
253
watch a car
watch-a-car
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
460
220
575
253
stop watching
stop-watching
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SWITCH
290
130
432
163
show_messages
show_messages
1
1
-1000

SWITCH
435
130
577
163
show-intentions
show-intentions
1
1
-1000

SLIDER
10
85
150
118
num-passengers
num-passengers
2
5
5.0
1
1
NIL
HORIZONTAL

SLIDER
155
85
315
118
%-carpoolers
%-carpoolers
0
100
60.0
1
1
%
HORIZONTAL

SLIDER
10
130
280
163
num-persons
num-persons
0
200
100.0
1
1
NIL
HORIZONTAL

SLIDER
10
175
165
208
ticks-of-waiting
ticks-of-waiting
50
1000
100.0
25
1
ticks
HORIZONTAL

SLIDER
170
175
315
208
waiting-discrepancy
waiting-discrepancy
15
80
15.0
1
1
%
HORIZONTAL

SWITCH
210
45
315
78
small-world
small-world
0
1
-1000

PLOT
1220
210
1435
375
Persons Carpooling
time
persons
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot num-persons-carpooling"

PLOT
1445
210
1660
375
Cars Carpooling
time
cars
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot num-cars-carpooling"

SWITCH
15
465
155
498
priority-areas
priority-areas
1
1
-1000

MONITOR
1280
390
1385
435
Persons Carpooling
num-persons-carpooling
17
1
11

MONITOR
1505
390
1602
435
Cars Carpooling
num-cars-carpooling
17
1
11

MONITOR
25
510
82
555
xop
xop-priority
3
1
11

MONITOR
95
510
152
555
yop
yop-priority
3
1
11

MONITOR
165
510
220
555
xdp
xdp-priority
3
1
11

MONITOR
235
510
292
555
ydp
ydp-priority
3
1
11

SLIDER
165
465
305
498
%-population
%-population
0
100
80.0
1
1
%
HORIZONTAL

BUTTON
90
570
227
603
Select Priority Area
choose-priority-area
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1670
210
1885
375
% of Persons Carpooling
time
% of persons
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot ( num-persons-carpooling / num-persons ) * 100"

PLOT
1225
455
1440
620
Persons Waiting for Car
time
persons
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot num-waiting-persons"

SWITCH
325
275
420
308
accidents
accidents
0
1
-1000

SLIDER
320
320
575
353
accident-probability
accident-probability
0.001
0.1
0.031
0.001
1
%
HORIZONTAL

SLIDER
320
360
575
393
ticks-of-accident
ticks-of-accident
50
1000
50.0
25
1
ticks
HORIZONTAL

SLIDER
320
405
575
438
accident-time-discrepancy
accident-time-discrepancy
15
80
15.0
1
1
%
HORIZONTAL

SWITCH
425
275
575
308
show-accident-roads
show-accident-roads
1
1
-1000

PLOT
1450
455
1665
620
Number of Accidents
Time
Number of Accidents
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot length accidents-list"

MONITOR
1505
640
1620
685
Numbers of Accidents
length accidents-list
0
1
11

INPUTBOX
340
460
557
520
log-file-name
simulation
1
0
String

SWITCH
355
540
457
573
log-write
log-write
1
1
-1000

BUTTON
470
540
547
573
Close log
close-file
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1675
455
1885
620
% of Parked Cars
Time
% of Cars
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (num-parked-cars / num-cars) * 100"

MONITOR
1750
640
1832
685
 Parked Cars
num-parked-cars
0
1
11

SWITCH
15
275
118
308
parking
parking
0
1
-1000

SLIDER
15
320
275
353
parking-probability
parking-probability
0.01
1
0.86
0.01
1
%
HORIZONTAL

SLIDER
15
360
275
393
ticks-of-parking
ticks-of-parking
50
1000
50.0
25
1
ticks
HORIZONTAL

SLIDER
15
405
275
438
parking-time-discrepancy
parking-time-discrepancy
15
80
15.0
1
1
%
HORIZONTAL

SWITCH
125
275
280
308
show-parking-patches
show-parking-patches
0
1
-1000

@#$#@#$#@
## ACKNOWLEDGMENT

This model is from Chapter Five of the book "Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo", by Uri Wilensky & William Rand.

* Wilensky, U. & Rand, W. (2015). Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo. Cambridge, MA. MIT Press.

This model is in the IABM Textbook folder of the NetLogo Models Library. The model, as well as any updates to the model, can also be found on the textbook website: http://www.intro-to-abm.com/.

## ERRATA

The code for this model differs somewhat from the code in the textbook. The textbook code calls the STAY procedure, which is not defined here. One of our suggestions in the "Extending the model" section below does, however, invite you to write a STAY procedure.

## WHAT IS IT?

The Traffic Grid Goal model simulates traffic moving in a city grid. It allows you to control traffic lights and global variables, such as the speed limit and the number of cars, and explore traffic dynamics.

This model extends the Traffic Grid model by giving the cars goals, namely to drive to and from work. It is the third in a series of traffic models that use different kinds of agent cognition. The agents in this model use goal-based cognition.

## HOW IT WORKS

Each time step, the cars face the next destination they are trying to get to (either work or home) and attempt to move forward at their current speed. If their current speed is less than the speed limit and there is no car directly in front of them, they accelerate. If there is a slower car in front of them, they match the speed of the slower car and decelerate. If there is a red light or a stopped car in front of them, they stop.

Each car has a house patch and a work patch. (The house patch turns yellow and the work patch turns orange for a car that you are watching.) The cars will alternately drive from their home to work and then from their work to home.

There are two different ways the lights can change. First, the user can change any light at any time by making the light current, and then clicking CHANGE LIGHT. Second, lights can change automatically, once per cycle. Initially, all lights will automatically change at the beginning of each cycle.

## HOW TO USE IT

Change the traffic grid (using the sliders GRID-SIZE-X and GRID-SIZE-Y) to make the desired number of lights. Change any other setting that you would like to change. Press the SETUP button.

At this time, you may configure the lights however you like, with any combination of auto/manual and any phase. Changes to the state of the current light are made using the CURRENT-AUTO?, CURRENT-PHASE and CHANGE LIGHT controls. You may select the current intersection using the SELECT INTERSECTION control. See below for details.

Start the simulation by pressing the GO button. You may continue to make changes to the lights while the simulation is running.

### Buttons

SETUP -- generates a new traffic grid based on the current GRID-SIZE-X and GRID-SIZE-Y and NUM-CARS number of cars. Each car chooses a home and work location. All lights are set to auto, and all phases are set to 0%.

GO -- runs the simulation indefinitely. Cars travel from their homes to their work and back.

CHANGE LIGHT -- changes the direction traffic may flow through the current light. A light can be changed manually even if it is operating in auto mode.

SELECT INTERSECTION -- allows you to select a new "current" intersection. When this button is depressed, click in the intersection which you would like to make current. When you've selected an intersection, the "current" label will move to the new intersection and this button will automatically pop up.

WATCH A CAR -- selects a car to watch. Sets the car's label to its goal. Displays the car's house in yellow and the car's work in orange. Opens inspectors for the watched car and its house and work.

STOP WATCHING -- stops watching the watched car and resets its labels and house and work colors.

### Sliders

SPEED-LIMIT -- sets the maximum speed for the cars.

NUM-CARS -- sets the number of cars in the simulation (you must press the SETUP button to see the change).

TICKS-PER-CYCLE -- sets the number of ticks that will elapse for each cycle. This has no effect on manual lights. This allows you to increase or decrease the granularity with which lights can automatically change.

GRID-SIZE-X -- sets the number of vertical roads there are (you must press the SETUP button to see the change).

GRID-SIZE-Y -- sets the number of horizontal roads there are (you must press the SETUP button to see the change).

CURRENT-PHASE -- controls when the current light changes, if it is in auto mode. The slider value represents the percentage of the way through each cycle at which the light should change. So, if the TICKS-PER-CYCLE is 20 and CURRENT-PHASE is 75%, the current light will switch at tick 15 of each cycle.

### Switches

POWER? -- toggles the presence of traffic lights.

CURRENT-AUTO? -- toggles the current light between automatic mode, where it changes once per cycle (according to CURRENT-PHASE), and manual, in which you directly control it with CHANGE LIGHT.

### Plots

STOPPED CARS -- displays the number of stopped cars over time.

AVERAGE SPEED OF CARS -- displays the average speed of cars over time.

AVERAGE WAIT TIME OF CARS -- displays the average time cars are stopped over time.

## THINGS TO NOTICE

How is this model different than the Traffic Grid model? The one thing you may see at first glance is that cars move in all directions instead of only left to right and top to bottom. You will probably agree that this looks much more realistic.

Another thing to notice is that, sometimes, cars get stuck: as explained in the book this is because the cars are mesuring the distance to their goals "as the bird flies", but reaching the goal sometimes require temporarily moving further from it (to get around a corner, for instance). A good way to witness that is to try the WATCH A CAR button until you find a car that is stuck. This situation could be prevented if the agents were more cognitively sophisticated. Do you think that it could also be avoided if the streets were layed out in a pattern different from the current one?

## THINGS TO TRY

You can change the "granularity" of the grid by using the GRID-SIZE-X and GRID-SIZE-Y sliders. Do cars get stuck more often with bigger values for GRID-SIZE-X and GRID-SIZE-Y, resulting in more streets, or smaller values, resulting in less streets? What if you use a big value for X and a small value for Y?

In the original Traffic Grid model from the model library, removing the traffic lights (by setting the POWER? switch to Off) quickly resulted in gridlock. Try it in this version of the model. Do you see a gridlock happening? Why do you think that is? Do you think it is more realistic than in the original model?

## EXTENDING THE MODEL

Can you improve the efficiency of the cars in their commute? In particular, can you think of a way to avoid cars getting "stuck" like we noticed above? Perhaps a simple rule like "don't go back to the patch you were previously on" would help. This should be simple to implement by giving the cars a (very) short term memory: something like a `previous-patch` variable that would be checked at the time of choosing the next patch to move to. Does it help in all situations? How would you deal with situations where the cars still get stuck?

Can you enable the cars to stay at home and work for some time before leaving? This would involve writing a STAY procedure that would be called instead moving the car around if the right condition is met (i.e., if the car has reached its current goal).

At the moment, only two of the four arms of each intersection have traffic lights on them. Having only two lights made sense in the original Traffic Grid model because the streets in that model were one-way streets, with traffic always flowing in the same direction. In our more complex model, cars can go in all directions, so it would be better if all four arms of the intersection had lights. What happens if you make that modification? Is the flow of traffic better or worse?

## RELATED MODELS

- "Traffic Basic": a simple model of the movement of cars on a highway.

- "Traffic Basic Utility": a version of "Traffic Basic" including a utility function for the cars.

- "Traffic Basic Adaptive": a version of "Traffic Basic" where cars adapt their acceleration to try and maintain a smooth flow of traffic.

- "Traffic Basic Adaptive Individuals": a version of "Traffic Basic Adaptive" where each car adapts individually, instead of all cars adapting in unison.

- "Traffic 2 Lanes": a more sophisticated two-lane version of the "Traffic Basic" model.

- "Traffic Intersection": a model of cars traveling through a single intersection.

- "Traffic Grid": a model of traffic moving in a city grid, with stoplights at the intersections.

- "Gridlock HubNet": a version of "Traffic Grid" where students control traffic lights in real-time.

- "Gridlock Alternate HubNet": a version of "Gridlock HubNet" where students can enter NetLogo code to plot custom metrics.

The traffic models from chapter 5 of the IABM textbook demonstrate different types of cognitive agents: "Traffic Basic Utility" demonstrates _utility-based agents_, "Traffic Grid Goal" demonstrates _goal-based agents_, and "Traffic Basic Adaptive" and "Traffic Basic Adaptive Individuals" demonstrate _adaptive agents_.

## HOW TO CITE

This model is part of the textbook, “Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo.”

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Rand, W., Wilensky, U. (2008).  NetLogo Traffic Grid Goal model.  http://ccl.northwestern.edu/netlogo/models/TrafficGridGoal.  Center for Connected Learning and Computer-Based Modeling, Northwestern Institute on Complex Systems, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the textbook as:

* Wilensky, U. & Rand, W. (2015). Introduction to Agent-Based Modeling: Modeling Natural, Social and Engineered Complex Systems with NetLogo. Cambridge, MA. MIT Press.

## COPYRIGHT AND LICENSE

Copyright 2008 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

<!-- 2008 Cite: Rand, W., Wilensky, U. -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
true
0
Polygon -7500403 true true 180 15 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 285 165 285 225 285 225 15 180 15
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -7500403 true true 195 195 58
Circle -7500403 true true 195 47 58

car-carpooling
true
0
Polygon -955883 true false 180 15 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 285 165 285 225 285 225 15 180 15
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -955883 true false 195 195 58
Circle -955883 true false 195 47 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
