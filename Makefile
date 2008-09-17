NAME=ShParser
PARSER_MODULE=lib/appchk/$(NAME).pm
EYAPP=eyapp
MKCMDLIST=./scripts/mkcmdlist2
CMDLIST_PREF=share/appchk/sh-cmdlist-

DEFAULT_MYSQL_HOST=kpm.igroup.ispras.ru
DEFAULT_MYSQL_DB=lsb
DEFAULT_MYSQL_USER=lsbuser
DEFAULT_MYSQL_PWD=


all: ShParser.pm

ShParser.pm: src/sh.yp
	$(EYAPP) -m $(NAME) -s $^ 2>/dev/null
	@mkdir -p lib/appchk 2>/dev/null
	mv $(NAME).pm $(PARSER_MODULE)

gensrc:
	@mkdir -p share/appchk
	if [ x"$$LSBUSER" = "x" ] ; then \
		export LSBUSER=$(DEFAULT_MYSQL_USER) LSBDBPASSWD=$(DEFAULT_MYSQL_PWD) \
		LSBDB=$(DEFAULT_MYSQL_DB) LSBDBHOST=$(DEFAULT_MYSQL_HOST) ; \
	fi ; \
	for lsbver in "3.0" "3.1" "3.2" "4.0"; do \
		$(MKCMDLIST) -v $$lsbver -o $(CMDLIST_PREF)$$lsbver || exit 1; \
	done

clean:
	@rm -f $(PARSER_MODULE) 2>/dev/null
	@rm -f $(CMDLIST_PREF)* 2>/dev/null
