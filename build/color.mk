# Beautify output with colors when available
#ifeq ($(shell tput -Txterm colors),8)
ifeq ($(shell tty 2> /dev/null || echo $$?),not a tty 1)
  LB:=
  RED:=
  GREEN:=
  NC:=
  CLEAR:=
  UPDATE:=
else
  export LB:=\033[1;34m
  export RED:=\033[1;31m
  export GREEN:=\033[1;32m
  export NC:=\033[0m
 ifndef VERBOSE
 ifndef NOUPDATE
  export CLEAR:=\033[0K
  export UPDATE:=$(CLEAR)\033[1A
 endif
 endif
endif
# O for open color, C for close color
export O:=$(LB)\#
export C:=\#$(NC)
