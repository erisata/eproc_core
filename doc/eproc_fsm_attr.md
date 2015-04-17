

# Module eproc_fsm_attr #
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `eproc_fsm_attr` behaviour.__
<br></br>
 Required callback functions: `init/2`, `handle_created/4`, `handle_updated/5`, `handle_removed/3`, `handle_event/4`.
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#action-3">action/3</a></td><td></td></tr><tr><td valign="top"><a href="#action-4">action/4</a></td><td></td></tr><tr><td valign="top"><a href="#apply_actions-4">apply_actions/4</a></td><td></td></tr><tr><td valign="top"><a href="#event-3">event/3</a></td><td></td></tr><tr><td valign="top"><a href="#init-5">init/5</a></td><td></td></tr><tr><td valign="top"><a href="#make_event-4">make_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#task-3">task/3</a></td><td></td></tr><tr><td valign="top"><a href="#transition_end-4">transition_end/4</a></td><td></td></tr><tr><td valign="top"><a href="#transition_start-4">transition_start/4</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="action-3"></a>

### action/3 ###

`action(Module, Name, Action) -> any()`


<a name="action-4"></a>

### action/4 ###

`action(Module, Name, Action, Scope) -> any()`


<a name="apply_actions-4"></a>

### apply_actions/4 ###


<pre><code>
apply_actions(AttrActions::[#attr_action{}] | undefined, Attributes::[#attribute{}], InstId::<a href="#type-inst_id">inst_id()</a>, TrnNr::<a href="#type-trn_nr">trn_nr()</a>) -&gt; {ok, [#attribute{}]}
</code></pre>

<br></br>



<a name="event-3"></a>

### event/3 ###

`event(InstId, Event, State) -> any()`


<a name="init-5"></a>

### init/5 ###

`init(InstId, SName, LastId, Store, ActiveAttrs) -> any()`


<a name="make_event-4"></a>

### make_event/4 ###

`make_event(Module, InstId, AttrNr, Event) -> any()`


<a name="task-3"></a>

### task/3 ###

`task(Module, Task, Opts) -> any()`


<a name="transition_end-4"></a>

### transition_end/4 ###

`transition_end(InstId, TrnNr, NextSName, State) -> any()`


<a name="transition_start-4"></a>

### transition_start/4 ###

`transition_start(InstId, TrnNr, SName, State) -> any()`


