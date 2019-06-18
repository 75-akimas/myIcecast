set("log.file.path","/tmp/<script>.log")
set("log.stdout", true)
set("server.telnet.port", 8001)
set("server.telnet", true)
set("server.timeout", -1.)

playlists = ref []
out = output.icecast(%mp3,
                     host="localhost",
                     port=8000,
                     password="hackme",
                     fallible=true,
                     encoding="UTF-8")
# is skipped flag
track.isSkipped = ref false;


# transition func
def transition(from, to)=
    if (!track.isSkipped) then
        track.isSkipped := false;
        add(normalize = false, [fade.initial(to), fade.final(from)]);
    else
        add(normalize = false, [to, from]);
    end
end

# extended crossfade
def crossfade.switch(~id = "", ~conservative = true, ~start_next=10., ~fade_in = 5., ~fade_out = 5., s)
  cross(id = id, conservative = conservative, duration = start_next, transition, s);
end

def add_playlist(uri) =
    def add_fadeout_command(s) =
        def fadeout(_) =
            track.isSkipped := true;
            source.skip(s)
            "Done!"
        end
        server.register(namespace="#{source.id(s)}",
                        usage="fadeout",
                        description="Fadeout the current song.",
                        "fadeout", fadeout)
    end
    def on_track_func(metadata) =
        log("on_track #{metadata['title']}")
    end
    blank = audio_to_stereo(single("blank.mp3"))
    security = request.equeue(id="#{uri}_sec")
    add_fadeout_command(security)
    log("set on end")
    security = fallback([security,blank])
    security = crossfade.switch(security);
    playlist = on_track(on_track_func, request.equeue(id="#{uri}_q"))
    playlist = fallback([playlist, security])
    output = out(mount=uri, playlist)
    playlists := list.append( [(uri,playlist),(uri,output)], !playlists )
    "Done!"
end

def delete_playlist(uri) =
  def parse_list(ret, current_element) =
    matching_sources = fst(ret)
    remaining_sources = snd(ret)
    current_uri = fst(current_element)
    if current_uri == uri then
      (list.append( [snd(current_element)],
                     matching_sources),
       remaining_sources)
    else
      (matching_sources,
       list.append([current_element],
                    remaining_sources))
    end
  end

  result = list.fold(parse_list, ([], []), !playlists)
  matching_sources = fst(result)
  remaining_sources = snd(result)
  playlists := remaining_sources
  if list.length(matching_sources) == 0 then
    "Error: no matching sources!"
  else
    list.iter(source.shutdown, matching_sources)
    "Done!"
  end
end

# 再生中の曲の終了時間をタイムスタンプで表示します。
def get_end_at(uri) =
  def parse_list(ret, current_element) =
    matching_sources = fst(ret)
    remaining_sources = snd(ret)
    current_uri = fst(current_element)
    if current_uri == uri then
      (list.append( [snd(current_element)],
                     matching_sources),
       remaining_sources)
    else
      (matching_sources,
       list.append([current_element],
                    remaining_sources))
    end
  end
  def get_remain(ret, current_element) =
    remain = source.remaining(current_element)
    now = gettimeofday()
    end_at = now + remain
    "#{now} #{remain} #{end_at}"
  end
  result = list.fold(parse_list, ([], []), !playlists)
  matching_sources = fst(result)
  ignore(snd(result))
  if list.length(matching_sources) == 0 then
    "Error: no matching sources!"
  else
    list.fold(get_remain, "", matching_sources)
  end
end

# Register server command
server.register(namespace="playlist",
                description="add a new mount point.",
                usage="add <uri>",
                "add",
                add_playlist)

server.register(namespace="playlist",
                description="delete a mount point",
                usage="delete <uri>",
                "delete",
                delete_playlist)

server.register(namespace="get-end-at",
                description="end-at of now playing",
                usage="end-at <uri>",
                "end-at",
                get_end_at)

#server.register(namespace="end",
#                description="end",
#                usage="end <uri>",
#                "end",
#                check_end)


output.dummy(blank())
