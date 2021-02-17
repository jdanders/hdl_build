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
LB:=\033[1;34m
RED:=\033[1;31m
GREEN:=\033[1;32m
NC:=\033[0m
ifneq (VERBOSE, 1)
CLEAR:=\033[0K
UPDATE:=$(CLEAR)\033[1A
endif
endif
# O for open color, C for close color
O:=$(LB)\#
C:=\#$(NC)
export
