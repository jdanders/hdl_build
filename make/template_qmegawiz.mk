$(IP_DIR)/modname/modname.qip: modpath
	@-rm -rf $(IP_DIR)/modname/
	@mkdir -p $(IP_DIR)/modname
	@cp modpath $(IP_DIR)/modname/modname.v
	@$(SCRIPTS)/run_print_err_only.sh \
	   "Generating ftype modname (started $(DATE))" \
	   "cd $(IP_DIR)/modname/ && $(QMW) -silent modname.v" \
	   $(BLOG_DIR)/ftype_ipgen_modname.log	@c

$(DONE_DIR)/qgen_ip.done: $(IP_DIR)/modname/modname.qip
