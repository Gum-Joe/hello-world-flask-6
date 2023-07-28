def test_index_page(client):
    response = client.get("/")
    assert b"<h2>What is your name?</h2>" in response.data

    response = client.post("/", data={"name": "Albus Dumbledore"})
    assert response.status_code == 200

    response = client.post("/")
    assert response.status_code == 400
