

# Module eproc_reg_gproc #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`eproc_registry`](eproc_registry.md), [`gen_server`](gen_server.md).
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#load-0">load/0</a></td><td></td></tr><tr><td valign="top"><a href="#ref-0">ref/0</a></td><td></td></tr><tr><td valign="top"><a href="#register_fsm-3">register_fsm/3</a></td><td></td></tr><tr><td valign="top"><a href="#register_name-2">register_name/2</a></td><td></td></tr><tr><td valign="top"><a href="#send-2">send/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td></td></tr><tr><td valign="top"><a href="#supervisor_child_specs-1">supervisor_child_specs/1</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#unregister_name-1">unregister_name/1</a></td><td></td></tr><tr><td valign="top"><a href="#whereis_name-1">whereis_name/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`


<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(Message, From, State) -> any()`


<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(Message, State) -> any()`


<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(X1, State) -> any()`


<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="load-0"></a>

### load/0 ###

`load() -> any()`


<a name="ref-0"></a>

### ref/0 ###

`ref() -> any()`


<a name="register_fsm-3"></a>

### register_fsm/3 ###

`register_fsm(RegistryArgs, InstId, Refs) -> any()`


<a name="register_name-2"></a>

### register_name/2 ###

`register_name(Name, Pid) -> any()`


<a name="send-2"></a>

### send/2 ###

`send(Pid, Message) -> any()`


<a name="start_link-2"></a>

### start_link/2 ###

`start_link(Name, Load) -> any()`


<a name="supervisor_child_specs-1"></a>

### supervisor_child_specs/1 ###

`supervisor_child_specs(RegistryArgs) -> any()`


<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`


<a name="unregister_name-1"></a>

### unregister_name/1 ###

`unregister_name(Name) -> any()`


<a name="whereis_name-1"></a>

### whereis_name/1 ###

`whereis_name(UnknownRefType) -> any()`


