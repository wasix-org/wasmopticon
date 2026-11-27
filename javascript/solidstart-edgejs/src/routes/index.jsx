import { action, redirect, useSearchParams } from "@solidjs/router";

const submitEcho = action(async (form) => {
  "use server";
  const message = String(form.get("message") ?? "");
  return redirect("/?receipt=" + encodeURIComponent(message), 303);
}, "submit-echo");

export default function Home() {
  const [params] = useSearchParams();
  return (
    <main>
      <h1>Hello from SolidStart on Wasmer Edge</h1>
      <output id="probe">{params.probe ?? "ready"}</output>
      <output id="receipt">{params.receipt ?? ""}</output>
      <form id="fixture-form" method="post" action={submitEcho}>
        <label>Message <input name="message" /></label>
        <button type="submit">Echo</button>
      </form>
    </main>
  );
}
