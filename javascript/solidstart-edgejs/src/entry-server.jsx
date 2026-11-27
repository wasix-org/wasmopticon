import { createHandler, StartServer } from "@solidjs/start/server";

function Document(props) {
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>SolidStart fixture</title>
        {props.assets}
      </head>
      <body>
        <div id="app">{props.children}</div>
        {props.scripts}
      </body>
    </html>
  );
}

export default createHandler(() => <StartServer document={Document} />, { mode: "async" });
