use actix_web::{HttpResponse, Responder, web};

pub async fn list_connections(path: Option<web::Path<String>>) -> impl Responder {
    let namespace = path.map(|p| p.into_inner());
    HttpResponse::Ok().body(format!("Listing connections for namespace: {:?}", namespace))
}

pub async fn get_connection(path: web::Path<(String, String)>) -> impl Responder {
    let (namespace, name) = path.into_inner();
    HttpResponse::Ok().body(format!("{}:{}", namespace, name))
}

pub async fn not_found() -> impl Responder {
    HttpResponse::NotFound().body("Not Found")
}
