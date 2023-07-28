import secrets
from flask import Flask, flash, abort, render_template, request

app = Flask(__name__)
app.config["SECRET_KEY"] = secrets.token_urlsafe(32)


@app.route("/", methods=["GET"])
def get_name():
    name = request.form.get("name")
    return render_template("index.html", name=name)


@app.route("/", methods=["POST"])
def post_name():
    if "name" not in request.form:
        abort(400)
    name = request.form.get("name")
    flash(f"Successfully added user {name}!")
    return render_template("index.html", name=name)
