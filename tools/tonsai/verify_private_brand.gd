extends SceneTree
## Probe the exported PCK, not loose staging files. Public fallback is intentional.
const REQUIRED := ["logo.png","Survivant.ttf","rect-button.png","rect-button-1.png","parch-portrait.png","parch-landscape.png","tribe-red.png","tribe-orange.png","tribe-blue.png","tribe-purple.png","tribe-green.png"]
func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    var required := args.has("--required") or bool(ProjectSettings.get_setting("private_branding/required",false))
    var report := {"required":required,"source":ProjectSettings.get_setting("marooning_build/implementation_sha",""),"resources":{},"missing":[],"passed":true}
    if required:
        for name: String in REQUIRED:
            var path := "res://private_brand/"+name
            var resource: Resource=load(path) if ResourceLoader.exists(path) else null
            var valid := false
            var detail := {}
            if name.ends_with(".ttf") and resource is FontFile:
                valid=resource.get_font_name()=="Survivant" and resource.data.size()>0 and resource.get_string_size("SURVIVOR ISLAND").x>0
                detail={"type":"FontFile","family":resource.get_font_name(),"bytes":resource.data.size()}
            elif resource is Texture2D:
                valid=resource.get_width()>0 and resource.get_height()>0
                detail={"type":"Texture2D","width":resource.get_width(),"height":resource.get_height()}
            detail["loaded"]=valid
            report.resources[name]=detail
            if not valid: report.missing.append(name)
        report.passed=report.missing.is_empty()
    var pack_index := args.find("--pack")
    if pack_index>=0: report["pack_sha256"]=FileAccess.get_sha256(args[pack_index+1])
    var output_index := args.find("--report")
    if output_index>=0:
        var file := FileAccess.open(args[output_index+1],FileAccess.WRITE)
        file.store_string(JSON.stringify(report,"  "))
    print("PRIVATE_BRAND_VALIDATION ",JSON.stringify(report))
    quit(0 if report.passed else 1)
