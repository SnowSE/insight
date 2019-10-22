$(document).ready(function() {
    $("#formSubmit").click(function(){
        console.log($("#imageUrl"));
        $("#imagePreview")[0].src = $("#imageUrl")[0].value;
    });


    $("#imageSubmit").click(function(){
        var formData = new FormData();
        var files = $('#imageFile')[0].files[0];
        formData.append('file',files);

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