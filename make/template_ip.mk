$(IP_DIR)/modname/modname.qip: $(IP_DIR)/modname.ftype
	@-rm -rf $(IP_DIR)/modname/
	@$(SCRIPTS)/run_print_err_only.sh \
	   "Generating ftype modname (started $(DATE))" \
	   "$(QGEN_IP) ipsearch $(IPGEN_ARGS)$(IP_DIR)/modname.ftype" \
	   $(BLOG_DIR)/ftype_ipgen_modname.log
	@-cp -a $(IP_DIR)/modname/synthesis/* $(IP_DIR)/modname 2>/dev/null || true

$(DONE_DIR)/qgen_ip.done: $(IP_DIR)/modname/modname.qip
