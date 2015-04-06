

# Module eproc_store #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `eproc_store` behaviour.__
<br></br>
 Required callback functions: `supervisor_child_specs/1`, `add_instance/2`, `add_transition/4`, `set_instance_killed/3`, `set_instance_suspended/3`, `set_instance_resuming/4`, `set_instance_resumed/3`, `load_instance/2`, `load_running/2`, `attr_task/3`, `get_instance/3`, `get_transition/4`, `get_state/4`, `get_message/3`, `get_node/1`.

<a name="types"></a>

## Data Types ##




### <a name="type-ref">ref()</a> ###


__abstract datatype__: `ref()`

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_instance-2">add_instance/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_transition-4">add_transition/4</a></td><td></td></tr><tr><td valign="top"><a href="#apply_transition-3">apply_transition/3</a></td><td></td></tr><tr><td valign="top"><a href="#attr_task-3">attr_task/3</a></td><td></td></tr><tr><td valign="top"><a href="#determine_transition_action-2">determine_transition_action/2</a></td><td></td></tr><tr><td valign="top"><a href="#get_instance-3">get_instance/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_message-3">get_message/3</a></td><td></td></tr><tr><td valign="top"><a href="#get_node-1">get_node/1</a></td><td></td></tr><tr><td valign="top"><a href="#get_state-4">get_state/4</a></td><td></td></tr><tr><td valign="top"><a href="#get_transition-4">get_transition/4</a></td><td></td></tr><tr><td valign="top"><a href="#instance_age_us-2">instance_age_us/2</a></td><td></td></tr><tr><td valign="top"><a href="#instance_filter_by_type-2">instance_filter_by_type/2</a></td><td></td></tr><tr><td valign="top"><a href="#instance_filter_to_ms-2">instance_filter_to_ms/2</a></td><td></td></tr><tr><td valign="top"><a href="#instance_filter_values-1">instance_filter_values/1</a></td><td></td></tr><tr><td valign="top"><a href="#instance_last_trn_time-1">instance_last_trn_time/1</a></td><td></td></tr><tr><td valign="top"><a href="#instance_sort-2">instance_sort/2</a></td><td></td></tr><tr><td valign="top"><a href="#intersect_lists-1">intersect_lists/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_instance_terminated-1">is_instance_terminated/1</a></td><td></td></tr><tr><td valign="top"><a href="#load_instance-2">load_instance/2</a></td><td></td></tr><tr><td valign="top"><a href="#load_running-2">load_running/2</a></td><td></td></tr><tr><td valign="top"><a href="#make_list-1">make_list/1</a></td><td></td></tr><tr><td valign="top"><a href="#make_resume_attempt-3">make_resume_attempt/3</a></td><td></td></tr><tr><td valign="top"><a href="#member_in_all-2">member_in_all/2</a></td><td></td></tr><tr><td valign="top"><a href="#ref-0">ref/0</a></td><td></td></tr><tr><td valign="top"><a href="#ref-2">ref/2</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_killed-3">set_instance_killed/3</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_resumed-3">set_instance_resumed/3</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_resuming-4">set_instance_resuming/4</a></td><td></td></tr><tr><td valign="top"><a href="#set_instance_suspended-3">set_instance_suspended/3</a></td><td></td></tr><tr><td valign="top"><a href="#sublist_opt-3">sublist_opt/3</a></td><td></td></tr><tr><td valign="top"><a href="#supervisor_child_specs-1">supervisor_child_specs/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_instance-2"></a>

### add_instance/2 ###

`add_instance(Store, Instance) -> any()`


<a name="add_transition-4"></a>

### add_transition/4 ###

`add_transition(Store, InstId, Transition, Messages) -> any()`


<a name="apply_transition-3"></a>

### apply_transition/3 ###

`apply_transition(Transition, InstState, InstId) -> any()`


<a name="attr_task-3"></a>

### attr_task/3 ###

`attr_task(Store, AttrModule, AttrTask) -> any()`


<a name="determine_transition_action-2"></a>

### determine_transition_action/2 ###

`determine_transition_action(Transition, OldStatus) -> any()`


<a name="get_instance-3"></a>

### get_instance/3 ###

`get_instance(Store, FsmRef, Query) -> any()`


<a name="get_message-3"></a>

### get_message/3 ###

`get_message(Store, MsgId, Query) -> any()`


<a name="get_node-1"></a>

### get_node/1 ###

`get_node(Store) -> any()`


<a name="get_state-4"></a>

### get_state/4 ###

`get_state(Store, FsmRef, SttNr, Query) -> any()`


<a name="get_transition-4"></a>

### get_transition/4 ###

`get_transition(Store, FsmRef, TrnNr, Query) -> any()`


<a name="instance_age_us-2"></a>

### instance_age_us/2 ###


<pre><code>
instance_age_us(Instance::#instance{}, Now::<a href="os.md#type-timestamp">os:timestamp()</a>) -&gt; integer()
</code></pre>

<br></br>



<a name="instance_filter_by_type-2"></a>

### instance_filter_by_type/2 ###


<pre><code>
instance_filter_by_type(InstanceFilters::list(), GroupTypes::[atom()]) -&gt; {ok, [[term()]], [term()]}
</code></pre>

<br></br>



<a name="instance_filter_to_ms-2"></a>

### instance_filter_to_ms/2 ###


<pre><code>
instance_filter_to_ms(InstanceFilters::list(), SkipFilters::[atom()]) -&gt; {ok, <a href="ets.md#type-match_spec">ets:match_spec()</a>}
</code></pre>

<br></br>



<a name="instance_filter_values-1"></a>

### instance_filter_values/1 ###


<pre><code>
instance_filter_values(Clauses::[{atom(), term() | [term()]}]) -&gt; [term()]
</code></pre>

<br></br>



<a name="instance_last_trn_time-1"></a>

### instance_last_trn_time/1 ###


<pre><code>
instance_last_trn_time(Instance::#instance{}) -&gt; <a href="os.md#type-timestamp">os:timestamp()</a> | undefined
</code></pre>

<br></br>



<a name="instance_sort-2"></a>

### instance_sort/2 ###


<pre><code>
instance_sort(Instance::[#instance{}], SortBy) -&gt; [#instance{}]
</code></pre>

<ul class="definitions"><li><code>SortBy = id | name | last_trn | created | module | status | age</code></li></ul>


<a name="intersect_lists-1"></a>

### intersect_lists/1 ###

`intersect_lists(Other) -> any()`


<a name="is_instance_terminated-1"></a>

### is_instance_terminated/1 ###

`is_instance_terminated(X1) -> any()`


<a name="load_instance-2"></a>

### load_instance/2 ###

`load_instance(Store, FsmRef) -> any()`


<a name="load_running-2"></a>

### load_running/2 ###

`load_running(Store, PartitionPred) -> any()`


<a name="make_list-1"></a>

### make_list/1 ###

`make_list(List) -> any()`


<a name="make_resume_attempt-3"></a>

### make_resume_attempt/3 ###

`make_resume_attempt(StateAction, UserAction, Resumes) -> any()`


<a name="member_in_all-2"></a>

### member_in_all/2 ###

`member_in_all(Element, Other) -> any()`


<a name="ref-0"></a>

### ref/0 ###


<pre><code>
ref() -&gt; {ok, <a href="#type-store_ref">store_ref()</a>}
</code></pre>

<br></br>



<a name="ref-2"></a>

### ref/2 ###


<pre><code>
ref(Module::module(), Args::term()) -&gt; {ok, <a href="#type-store_ref">store_ref()</a>}
</code></pre>

<br></br>



<a name="set_instance_killed-3"></a>

### set_instance_killed/3 ###

`set_instance_killed(Store, FsmRef, UserAction) -> any()`


<a name="set_instance_resumed-3"></a>

### set_instance_resumed/3 ###

`set_instance_resumed(Store, InstId, TrnNr) -> any()`


<a name="set_instance_resuming-4"></a>

### set_instance_resuming/4 ###

`set_instance_resuming(Store, FsmRef, StateAction, UserAction) -> any()`


<a name="set_instance_suspended-3"></a>

### set_instance_suspended/3 ###

`set_instance_suspended(Store, FsmRef, Reason) -> any()`


<a name="sublist_opt-3"></a>

### sublist_opt/3 ###

`sublist_opt(List, From, Count) -> any()`


<a name="supervisor_child_specs-1"></a>

### supervisor_child_specs/1 ###


<pre><code>
supervisor_child_specs(Store::<a href="#type-store_ref">store_ref()</a>) -&gt; {ok, list()}
</code></pre>

<br></br>



