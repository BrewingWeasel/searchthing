import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import htmgrrrl.{Characters, StartElement}
import website_provider

pub fn main() {
  let assert Ok(provider) =
    website_provider.new([
      "https://www.15min.lt", "https://www.lrt.lt", "https://www.delfi.lt",
      "https://www.knygos.lt", "https://www.patogupirkti.lt",
      "https://www.varle.lt", "https://www.vz.lt", "https://www.lrytas.lt",
      "https://www.gismeteo.lt", "https://www.kauno.diena.lt",
      "https://lt.wikipedia.org", "https://www.beatosvirtuve.lt",
      "https://www.tele2.lt", "https://www.pigu.lt", "https://www.senukai.lt",
      "https://www.bilietai.lt", "https://www.go3.lt", "https://www.telia.lt",
      "https://www.novastar.lt/", "https://shop.zalgiris.lt/",
    ])
  list.range(1, 10)
  |> list.each(fn(x) { process.start(fn() { get_site(x, provider) }, False) })
  process.sleep_forever()
}

fn get_site(t, provider) {
  let assert Ok(url) = website_provider.get_url(provider)
  io.println(string.inspect(t) <> ": parsing " <> url)
  let assert Ok(req) = request.to(url)

  use resp <- result.try(
    req
    |> request.set_header("User-Agent", "lolbot")
    |> httpc.send(),
  )

  let assert Ok(basic) =
    uri.parse(url)
    |> result.then(uri.origin)

  let _ = case response.get_header(resp, "content-type") {
    Ok("text/html" <> _) -> handle_html(provider, basic, resp.body)
    _ -> Ok(Nil)
  }
  io.println(string.inspect(t) <> ": parsed " <> url)
  get_site(t, provider)
}

fn handle_html(provider, basic_site: String, body: String) {
  let take_text = fn(state, _line, event) {
    case event {
      Characters(text) -> [text, ..state]
      StartElement(_, "a", _, attributes) -> {
        list.each(attributes, fn(attr) {
          case attr.value {
            "/" <> _ if attr.name == "href" -> {
              website_provider.add_url(provider, basic_site <> attr.value)
            }
            "h" <> _ if attr.name == "href" -> {
              website_provider.add_url(provider, attr.value)
            }
            _ -> Nil
          }
        })
        state
      }
      _ -> state
    }
  }
  let _ = htmgrrrl.sax(body, [], take_text)
  Ok(Nil)
}
