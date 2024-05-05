import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/uri

const timeout: Int = 5_000_000

// TODO: what should the timeout be?

pub type Message {
  GetUrl(reply_with: Subject(Result(Url, Nil)))
  AddUrl(Url)
  Kill
}

type Url =
  String

type State {
  State(
    url_queue: Dict(Url, List(Url)),
    visited_urls: Set(Url),
    robots_rules: Dict(Url, String),
    next_url: List(Url),
  )
}

pub fn new(
  starting_urls: List(Url),
) -> Result(Subject(Message), actor.StartError) {
  let urls =
    starting_urls
    |> list.map(fn(x) { #(x, [x]) })
    |> dict.from_list()
  actor.start(State(urls, set.new(), dict.new(), []), handle_message)
}

pub fn get_url(state: Subject(Message)) -> Result(Url, Nil) {
  actor.call(state, GetUrl(_), timeout)
}

pub fn add_url(state: Subject(Message), url: String) {
  actor.send(state, AddUrl(url))
}

pub fn close(state: Subject(Message)) -> Nil {
  actor.send(state, Kill)
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    GetUrl(client) -> {
      io.debug(dict.keys(state.url_queue))
      case get_url_from_domain(state.next_url, state) {
        #(Ok(url), state) -> {
          actor.send(client, Ok(url))
          actor.continue(
            State(..state, visited_urls: set.insert(state.visited_urls, url)),
          )
        }
        #(Error(Nil), state) ->
          case get_url_from_domain(dict.keys(state.url_queue), state) {
            #(Ok(url), state) -> {
              actor.send(client, Ok(url))
              actor.continue(
                State(
                  ..state,
                  visited_urls: set.insert(state.visited_urls, url),
                ),
              )
            }
            #(Error(Nil), state) -> {
              actor.send(client, Error(Nil))
              actor.continue(state)
            }
          }
      }
    }
    AddUrl(url) -> {
      use <- bool.lazy_guard(
        when: set.contains(state.visited_urls, url),
        return: fn() { actor.continue(state) },
      )
      case
        uri.parse(url)
        |> result.then(uri.origin)
      {
        Error(Nil) -> actor.continue(state)
        Ok(root_url) -> {
          use <- bool.lazy_guard(
            when: bool.negate(string.ends_with(root_url, ".lt/")),
            return: fn() { actor.continue(state) },
          )
          actor.continue(
            State(
              ..state,
              url_queue: dict.update(state.url_queue, root_url, fn(urls) {
                case urls {
                  option.Some(urls) -> [url, ..urls]
                  option.None -> [url]
                }
              }),
            ),
          )
        }
      }
    }
    Kill -> actor.Stop(process.Normal)
  }
}

fn get_url_from_domain(
  domains: List(Url),
  state: State,
) -> #(Result(Url, Nil), State) {
  case domains {
    [] -> #(Error(Nil), state)
    [domain, ..next_domains] ->
      state.url_queue
      |> dict.get(domain)
      |> result.then(fn(x) {
        case x {
          [url, ..urls] -> {
            Ok(#(url, urls))
          }
          [] -> Error(Nil)
        }
      })
      |> result.map(fn(x) {
        #(
          Ok(x.0),
          State(..state, url_queue: dict.insert(state.url_queue, domain, x.1)),
        )
      })
      |> result.lazy_unwrap(fn() { get_url_from_domain(next_domains, state) })
  }
}
