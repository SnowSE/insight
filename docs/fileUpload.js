$(document).ready(function() {
    $("#urlForm").focusout(function(e){
        if($("#imageUrl").val().length == 0){
            $("#displayImageUrl")[0].src = "https://semantic-ui.com/images/wireframe/image.png"
        }
        else{
            $("#displayImageUrl")[0].src = $("#imageUrl")[0].value;
        }
    });

    $("#imageForm").change(function(e){
        var target = e.target || window.event.srcElement,
        files = target.files;
        debugger;

        if (FileReader && files && files.length) {
            var fr = new FileReader();
            fr.onload = function () {
                $("#displayImageFile")[0].src = fr.result;
            }
            fr.readAsDataURL(files[0]);
        }

    });

    $("#imageSubmit").click(function(){
        var formData = new FormData();
        var files = $('#imageFile')[0].files[0];
        formData.append('image',files);

        console.log(formData.image);
        $("#imagePreview")[0].src = files.name;

        $.ajax({
            url: 'someurl',
            type: 'POST',
            headers: {  'Access-Control-Allow-Origin': "*" },
            data: formData,
            contentType: false,
            processData: false,
            success: function(response){
                debugger;
                if(response != 0){
                    $("#imagePreview").attr("src",response); 
                }else{
                    alert('file not uploaded');
                }
            },
        });
    });
});