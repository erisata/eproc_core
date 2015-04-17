

# Module eproc_store_ets #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`eproc_store`](eproc_store.md), [`gen_server`](gen_server.md).
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_instance-2">add_instance/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_transition-4">add_transition/4</a></td><td></td></tr><tr><td valign="top"><a href="#attr_task-3">attr_task/3</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_instance-3">get_instance/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_message-3">get_message/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_node-1">get_node/1</a></td><td></td></tr><tr><td valign="top"><a href="#get_state-4">get_state/4</a></td><td></td></tr><tr><td valign="top"><a href="#get_transition-4">get_transition/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#load_instance-2">load_instance/2</a></td><td></td></tr><tr><td valign="top"><a href="#load_running-2">load_running/2</a></td><td></td></tr><tr><td valign="top"><a href="#ref-0">ref/0</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_killed-3">set_instance_killed/3</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_resumed-3">set_instance_resumed/3</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_resuming-4">set_instance_resuming/4</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_suspended-3">set_instance_suspended/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#supervisor_child_specs-1">supervisor_child_specs/1</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_instance-2"></a>

### add_instance/2 ###

`add_instance(StoreArgs, Instance) -> any()`


<a name="add_transition-4"></a>

### add_transition/4 ###

`add_transition(StoreArgs, InstId, Transition, Messages) -> any()`


<a name="attr_task-3"></a>

### attr_task/3 ###

`attr_task(StoreArgs, AttrModule, AttrTask) -> any()`


<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`


<a name="get_instance-3"></a>

### get_instance/3 ###

`get_instance(StoreArgs, FsmRef, Query) -> any()`


<a name="get_message-3"></a>

### get_message/3 ###

`get_message(StoreArgs, MsgId, X3) -> any()`


<a name="get_node-1"></a>

### get_node/1 ###

`get_node(StoreArgs) -> any()`


<a name="get_state-4"></a>

### get_state/4 ###

`get_state(StoreArgs, FsmRef, SttNr, X4) -> any()`


<a name="get_transition-4"></a>

### get_transition/4 ###

`get_transition(StoreArgs, FsmRef, TrnNr, X4) -> any()`


<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(Event, From, State) -> any()`


<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(Event, State) -> any()`


<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Event, State) -> any()`


<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="load_instance-2"></a>

### load_instance/2 ###

`load_instance(StoreArgs, FsmRef) -> any()`


<a name="load_running-2"></a>

### load_running/2 ###

`load_running(StoreArgs, PartitionPred) -> any()`


<a name="ref-0"></a>

### ref/0 ###

`ref() -> any()`


<a name="set_instance_killed-3"></a>

### set_instance_killed/3 ###

`set_instance_killed(StoreArgs, FsmRef, UserAction) -> any()`


<a name="set_instance_resumed-3"></a>

### set_instance_resumed/3 ###

`set_instance_resumed(StoreArgs, InstId, TrnNr) -> any()`


<a name="set_instance_resuming-4"></a>

### set_instance_resuming/4 ###

`set_instance_resuming(StoreArgs, FsmRef, StateAction, UserAction) -> any()`


<a name="set_instance_suspended-3"></a>

### set_instance_suspended/3 ###

`set_instance_suspended(StoreArgs, FsmRef, Reason) -> any()`


<a name="start_link-1"></a>

### start_link/1 ###

`start_link(Name) -> any()`


<a name="supervisor_child_specs-1"></a>

### supervisor_child_specs/1 ###

`supervisor_child_specs(StoreArgs) -> any()`


<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`


