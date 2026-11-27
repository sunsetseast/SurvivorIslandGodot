class_name MarooningCollectionStation
extends Node3D
## Non-collectible, tribal collection bin. Approach positions are separate from its body.
func build(tribe: Dictionary) -> void:
    var model := MarooningSupplyVisual.new()
    model.build("basket")
    model.scale = Vector3(1.5,1.5,2.5)
    add_child(model)
    var body := StaticBody3D.new()
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(.7,.65,1.6)
    collider.shape = shape
    collider.position.y = .325
    body.add_child(collider)
    add_child(body)
    var band := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(.76,.15,1.65)
    band.mesh = mesh
    band.position.y = .45
    band.material_override = MarooningBay.material(Color(tribe.color))
    add_child(band)
    var flag := Label3D.new()
    flag.text = tribe.name+"\nCOLLECTION BASKET"
    flag.position.y = 2.25
    flag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    flag.font_size = 38
    flag.pixel_size = .0013
    flag.fixed_size = true
    flag.modulate = Color(tribe.color).lightened(.4)
    flag.outline_size = 10
    add_child(flag)

    # Marked overflow staging belongs to the station, never to the collectible pool.
    var pallet := MeshInstance3D.new()
    pallet.name = "SecuredOverflowPallet"
    var boards := BoxMesh.new()
    boards.size = Vector3(.75,.08,1.7)
    pallet.mesh = boards
    pallet.position = Vector3(0,.04,2.1)
    pallet.material_override = MarooningBay.timber()
    add_child(pallet)
    var cargo_label := Label3D.new()
    cargo_label.text = "SECURED CARGO"
    cargo_label.position = Vector3(0,.3,2.1)
    cargo_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    cargo_label.font_size = 32
    cargo_label.pixel_size = .0013
    cargo_label.fixed_size = true
    add_child(cargo_label)
