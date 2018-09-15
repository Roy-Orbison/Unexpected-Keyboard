open Android_content
open Android_inputmethodservice
open Android_util
open Android_view

external _hack : unit -> unit = "Java_juloo_javacaml_Caml_startup"

(** Send a character through the current input connection *)
let send_char ims cp =
	let ic = Input_method_service.get_current_input_connection ims in
	let txt = Utils.java_string_of_code_point cp in
	ignore (Input_connection.commit_text ic txt 1)

let key_char_map = lazy Key_character_map.(load (get'virtual_keyboard ()))

(** Send a character as 2 key events (down and up)
	Allows setting the meta field *)
let send_char_meta ims cp meta =
	match Char.chr cp with
	| exception _	-> ()
	| c				->
		let events =
			let chars = Jarray.create_char 1 in
			Jarray.set_char chars 0 c;
			Key_character_map.get_events (Lazy.force key_char_map) chars
		in
		let ic = Input_method_service.get_current_input_connection ims in
		for i = 0 to Jarray.length events - 1 do
			let ev = Jarray.get_object events i in
			let action = Key_event.get_action ev
			and code = Key_event.get_key_code ev in
			let ev = Key_event.create' 1L 1L action code 1 meta in
			ignore (Input_connection.send_key_event ic ev)
		done

(** Likes `Input_method_service.send_down_up_key_events`
		with an extra `meta` parameter *)
let send_event ims evt meta =
	let code =
		let open Key_event in
		match evt with
		| Key.Escape	-> get'keycode_escape ()
		| Tab			-> get'keycode_tab ()
		| Backspace		-> get'keycode_del ()
		| Delete		-> get'keycode_forward_del ()
		| Enter			-> get'keycode_enter ()
		| Left			-> get'keycode_dpad_left ()
		| Right			-> get'keycode_dpad_right ()
		| Up			-> get'keycode_dpad_up ()
		| Down			-> get'keycode_dpad_down ()
		| Page_up		-> get'keycode_page_up ()
		| Page_down		-> get'keycode_page_down ()
		| Home			-> get'keycode_home ()
		| End			-> get'keycode_move_end ()
	in
	let time = Android_os.System_clock.uptime_millis () in
	let mk_event action =
		let flags = Key_event.(get'flag_keep_touch_mode ()
				lor get'flag_soft_keyboard ()) in
		Key_event.create time time action code 0 meta ~-1 0 flags
	in
	let ic = Input_method_service.get_current_input_connection ims in
	let send = Input_connection.send_key_event ic in
	ignore (send (mk_event (Key_event.get'action_down ()))
		&& send (mk_event (Key_event.get'action_up ())))

let keyboard_service ims =
	let view () =
		let ims' = object
			method send = function
				| Key.Char (c, 0)	-> send_char ims c
				| Char (c, meta)	-> send_char_meta ims c meta
				| Event (ev, meta)	-> send_event ims ev meta
		end in
		let root, view = ComponentTmpl_T.root_one Keyboard_view.view in
		Component.run (Keyboard_view.create ims', []) root (fun t f -> f t)
		|> Lwt.async;
		view
	in
	object
		val view = lazy (view ())
		method onInitializeInterface = ()
		method onBindInput = ()
		method onCreateInputView = Lazy.force view
		method onCreateCandidatesView = Java.null
		method onStartInput _ _ = ()
	end

let () =
	Printexc.record_backtrace true;
	Android_enable_logging.enable "UNEXPECTED KEYBOARD";
	let service = Keyboard_service.keyboard_service create update draw in
	UnexpectedKeyboardService.register service
