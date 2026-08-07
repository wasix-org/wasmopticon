import type { APIRoute } from "astro";
import { eq } from "drizzle-orm";
import { db } from "../db";
import { todos } from "../db/schema";

function redirect(location = "/") {
  return new Response(null, { status: 303, headers: { Location: location } });
}

function parseId(value: FormDataEntryValue | null) {
  if (typeof value !== "string" || !/^\d+$/.test(value)) return null;
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}

export const POST: APIRoute = async ({ request }) => {
  const form = await request.formData();
  const action = form.get("action");

  if (action === "create") {
    const value = form.get("title");
    const title = typeof value === "string" ? value.trim() : "";

    if (!title || title.length > 200) {
      return redirect("/?error=Todo+must+be+between+1+and+200+characters");
    }

    await db.insert(todos).values({ title });
    return redirect();
  }

  const id = parseId(form.get("id"));
  if (!id) return new Response("Invalid todo id", { status: 400 });

  if (action === "toggle") {
    await db
      .update(todos)
      .set({ completed: form.get("completed") === "true" })
      .where(eq(todos.id, id));
    return redirect();
  }

  if (action === "delete") {
    await db.delete(todos).where(eq(todos.id, id));
    return redirect();
  }

  return new Response("Unknown action", { status: 400 });
};
