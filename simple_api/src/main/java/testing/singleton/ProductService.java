package testing.singleton;

public class ProductService {

    private final ProductDAO productDAO;

    public ProductService(ProductDAO productDAO) {
        this.productDAO = productDAO;
    }

    public Product getProduct(String productName) {
        Product product = CacheManager.getInstance().getValues(productName, Product.class);
        if (product == null) {
            product = productDAO.getProduct(productName);
            CacheManager.getInstance().setValue(productName, product);
        }

        return product;
    }
}
