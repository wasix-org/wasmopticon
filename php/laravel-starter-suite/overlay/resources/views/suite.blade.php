<!doctype html>
<html lang="en">
<head><title>WASIX Laravel form</title></head>
<body>
<form method="post" action="/suite/form">
    @csrf
    <label>Name <input name="name" required></label>
    <button type="submit">Save</button>
</form>
@if ($email)
    <p id="session-email">{{ $email }}</p>
@endif
</body>
</html>
